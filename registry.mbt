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
  if channel_index >= 0 {
    let revisions = self.channels[channel_index].revisions
    if !revisions.is_empty() && revisions[revisions.length() - 1].rule == rule {
      return registry_failure(
        normalized, "registry.rule.duplicate", "rule is identical to the latest revision",
      )
    }
  }
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

///|
/// Parse and publish a dynamic JSON rule document. Parser diagnostics are
/// returned as registry errors so control planes do not need a second error
/// channel for malformed submissions.
pub fn RuleRegistry::publish_json(
  self : RuleRegistry,
  channel : String,
  schema_json : String,
  note? : String = "",
  published_by? : String = "",
) -> RegistryResult {
  let parsed = parse_rule_document(schema_json)
  match parsed.rule {
    None => {
      let message = if parsed.errors.is_empty() {
        "rule document could not be parsed"
      } else {
        parsed.errors[0]
      }
      registry_failure(channel, "registry.schema.invalid", message)
    }
    Some(rule) =>
      self.publish_rule(channel, rule, schema_json~, note~, published_by~)
  }
}

///|
/// Atomically select one published revision for subsequent validations.
pub fn RuleRegistry::activate(
  self : RuleRegistry,
  channel : String,
  version : Int,
) -> RegistryResult {
  let channel_index = registry_channel_index(self, channel)
  if channel_index < 0 {
    return registry_failure(
      channel, "registry.channel.missing", "channel does not exist",
    )
  }
  let entry = self.channels[channel_index]
  if revision_index(entry, version) < 0 {
    return registry_failure(
      channel, "registry.version.missing", "revision does not exist",
    )
  }
  self.channels[channel_index] = { ..entry, active_version: Some(version) }
  registry_success(channel, Some(version), "rule revision activated")
}

///|
/// Move the active pointer to the immediately preceding revision.
pub fn RuleRegistry::rollback(
  self : RuleRegistry,
  channel : String,
) -> RegistryResult {
  let channel_index = registry_channel_index(self, channel)
  if channel_index < 0 {
    return registry_failure(
      channel, "registry.channel.missing", "channel does not exist",
    )
  }
  let entry = self.channels[channel_index]
  let active = match entry.active_version {
    None =>
      return registry_failure(
        channel, "registry.active.missing", "channel has no active revision",
      )
    Some(version) => version
  }
  let mut candidate = 0
  for revision in entry.revisions {
    if revision.version < active && revision.version > candidate {
      candidate = revision.version
    }
  }
  if candidate == 0 {
    return registry_failure(
      channel, "registry.rollback.unavailable", "no earlier revision is available",
    )
  }
  self.activate(channel, candidate)
}

///|
/// Validate one parsed JSON value and record the active version used.
pub fn RuleRegistry::validate_active(
  self : RuleRegistry,
  channel : String,
  value : Json,
  options? : ValidationOptions = default_validation_options(),
) -> RegistryValidationResult {
  match self.active_revision(channel) {
    None => { found: false, channel, version: None, report: None }
    Some(revision) =>
      {
        found: true,
        channel,
        version: Some(revision.version),
        report: Some(validate(revision.rule, value, options~)),
      }
  }
}

///|
pub fn RuleRegistry::validate_active_json(
  self : RuleRegistry,
  channel : String,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> RegistryValidationResult {
  match self.active_revision(channel) {
    None => { found: false, channel, version: None, report: None }
    Some(revision) =>
      {
        found: true,
        channel,
        version: Some(revision.version),
        report: Some(validate_json(revision.rule, text, options~)),
      }
  }
}

///|
pub fn RuleRegistry::validate_active_json_array(
  self : RuleRegistry,
  channel : String,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> RegistryBatchResult {
  match self.active_revision(channel) {
    None => { found: false, channel, version: None, report: None }
    Some(revision) =>
      {
        found: true,
        channel,
        version: Some(revision.version),
        report: Some(validate_json_array(revision.rule, text, options~)),
      }
  }
}

///|
pub fn RuleRegistry::validate_active_json_lines(
  self : RuleRegistry,
  channel : String,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> RegistryBatchResult {
  match self.active_revision(channel) {
    None => { found: false, channel, version: None, report: None }
    Some(revision) =>
      {
        found: true,
        channel,
        version: Some(revision.version),
        report: Some(validate_json_lines(revision.rule, text, options~)),
      }
  }
}

///|
/// Publish only when every supplied compatibility case satisfies the
/// candidate. This gives CI and control planes an atomic test-and-publish
/// primitive instead of requiring a race-prone validation step beforehand.
pub fn RuleRegistry::publish_json_checked(
  self : RuleRegistry,
  channel : String,
  schema_json : String,
  cases : Array[ValidationCase],
  note? : String = "",
  published_by? : String = "",
  options? : ValidationOptions = default_validation_options(),
) -> RegistryGateResult {
  let parsed = parse_rule_document(schema_json)
  let candidate = match parsed.rule {
    None => {
      let message = if parsed.errors.is_empty() {
        "rule document could not be parsed"
      } else {
        parsed.errors[0]
      }
      return {
        published: false,
        result: registry_failure(channel, "registry.schema.invalid", message),
        compatibility: None,
      }
    }
    Some(rule) => rule
  }
  let compatibility = validate_batch(candidate, cases, options~)
  if !compatibility.valid {
    return {
      published: false,
      result: registry_failure(
        channel, "registry.gate.failed", "candidate rejected by compatibility cases",
      ),
      compatibility: Some(compatibility),
    }
  }
  let result = self.publish_rule(
    channel,
    candidate,
    schema_json~,
    note~,
    published_by~,
  )
  { published: result.ok, result, compatibility: Some(compatibility) }
}

///|
/// Produce a deterministic, backend-independent persistence manifest.
pub fn RuleRegistry::manifest(self : RuleRegistry) -> RegistryManifest {
  let channels : Array[RegistryChannelInfo] = []
  for channel in self.channels {
    let revisions : Array[RegistryRevisionInfo] = []
    for revision in channel.revisions {
      revisions.push({
        version: revision.version,
        note: revision.note,
        published_by: revision.published_by,
        schema_json: revision.schema_json,
      })
    }
    channels.push({
      name: channel.name,
      active_version: channel.active_version,
      revisions,
    })
  }
  { format_version: 1, channels }
}

///|
pub fn RuleRegistry::manifest_json(
  self : RuleRegistry,
  indent? : Int = 2,
) -> String {
  self.manifest().to_json().stringify(indent~)
}

///|
/// Restore a complete registry from a manifest. Loading is transactional: a
/// malformed schema, non-sequential version or invalid active pointer rejects
/// the whole document and does not expose a partially restored registry.
pub fn rule_registry_from_manifest(text : String) -> RuleRegistry? {
  let value = @json.parse(text) catch { _ => return None }
  let manifest : RegistryManifest = @json.from_json(value) catch {
    _ => return None
  }
  if manifest.format_version != 1 {
    return None
  }
  let registry = new_rule_registry()
  for channel in manifest.channels {
    if channel.revisions.is_empty() {
      return None
    }
    for index = 0; index < channel.revisions.length(); index = index + 1 {
      let revision = channel.revisions[index]
      if revision.version != index + 1 {
        return None
      }
      let result = registry.publish_json(
        channel.name,
        revision.schema_json,
        note=revision.note,
        published_by=revision.published_by,
      )
      if !result.ok {
        return None
      }
    }
    let active = match channel.active_version {
      None => return None
      Some(version) => version
    }
    if !registry.activate(channel.name, active).ok {
      return None
    }
  }
  Some(registry)
}
