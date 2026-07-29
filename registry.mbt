///|
fn registry_success(
  channel : String,
  version : Int?,
  message : String,
) -> RegistryResult {
  { ok: true, code: "registry.ok", message, channel, version }
}

///|
fn registry_failure(
  channel : String,
  code : String,
  message : String,
) -> RegistryResult {
  { ok: false, code, message, channel, version: None }
}

///|
fn registry_channel_index(registry : RuleRegistry, name : String) -> Int {
  for index = 0; index < registry.channels.length(); index = index + 1 {
    if registry.channels[index].name == name {
      return index
    }
  }
  -1
}

///|
fn revision_index(channel : RuleChannel, version : Int) -> Int {
  for index = 0; index < channel.revisions.length(); index = index + 1 {
    if channel.revisions[index].version == version {
      return index
    }
  }
  -1
}

///|
/// Create an isolated registry. The value can be passed freely because its
/// channel array retains reference semantics for intentional mutations.
pub fn new_rule_registry() -> RuleRegistry {
  { channels: [] }
}

///|
pub fn RuleRegistry::channel_count(self : RuleRegistry) -> Int {
  self.channels.length()
}

///|
pub fn RuleRegistry::channel_names(self : RuleRegistry) -> Array[String] {
  self.channels.map(channel => channel.name)
}

///|
pub fn RuleRegistry::revision_count(
  self : RuleRegistry,
  channel : String,
) -> Int {
  let index = registry_channel_index(self, channel)
  if index < 0 {
    0
  } else {
    self.channels[index].revisions.length()
  }
}

///|
pub fn RuleRegistry::active_version(
  self : RuleRegistry,
  channel : String,
) -> Int? {
  let index = registry_channel_index(self, channel)
  if index < 0 {
    None
  } else {
    self.channels[index].active_version
  }
}

///|
pub fn RuleRegistry::get_revision(
  self : RuleRegistry,
  channel : String,
  version : Int,
) -> RuleRevision? {
  let channel_index = registry_channel_index(self, channel)
  if channel_index < 0 {
    return None
  }
  let entry = self.channels[channel_index]
  let index = revision_index(entry, version)
  if index < 0 {
    None
  } else {
    Some(entry.revisions[index])
  }
}

///|
pub fn RuleRegistry::active_revision(
  self : RuleRegistry,
  channel : String,
) -> RuleRevision? {
  match self.active_version(channel) {
    None => None
    Some(version) => self.get_revision(channel, version)
  }
}

///|
pub fn RuleRegistry::list_revisions(
  self : RuleRegistry,
  channel : String,
) -> Array[RuleRevision] {
  let index = registry_channel_index(self, channel)
  if index < 0 {
    []
  } else {
    self.channels[index].revisions.map(revision => revision)
  }
}

///|
/// Append one immutable revision. The first revision becomes active so a
/// freshly created channel is usable immediately; later revisions remain
/// inactive until explicitly promoted.
pub fn RuleRegistry::publish_rule(
  self : RuleRegistry,
  channel : String,
  rule : Rule,
  schema_json? : String = "",
  note? : String = "",
  published_by? : String = "",
) -> RegistryResult {
  let normalized = channel.trim().to_owned()
  if normalized.is_empty() {
    return registry_failure(
      channel, "registry.channel.empty", "channel name is required",
    )
  }
  if !is_slug(normalized) {
    return registry_failure(
      channel, "registry.channel.invalid", "channel must be a lowercase slug",
    )
  }
  if !rule_is_well_formed(rule) {
    return registry_failure(
      normalized, "registry.rule.invalid", "rule is not well formed",
    )
  }
  let channel_index = registry_channel_index(self, normalized)
  let version = if channel_index < 0 {
    1
  } else {
    self.channels[channel_index].revisions.length() + 1
  }
  let encoded = if schema_json.is_empty() {
    rule_to_json(rule)
  } else {
    schema_json
  }
  let revision = {
    channel: normalized,
    version,
    rule,
    schema_json: encoded,
    note,
    published_by,
  }
  if channel_index < 0 {
    self.channels.push({
      name: normalized,
      active_version: Some(version),
      revisions: [revision],
    })
  } else {
    self.channels[channel_index].revisions.push(revision)
  }
  registry_success(normalized, Some(version), "rule revision published")
}
