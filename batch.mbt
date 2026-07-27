///|
/// Validate independent values with one reusable rule.
pub fn validate_batch(
  rule : Rule,
  cases : Array[ValidationCase],
  options? : ValidationOptions = default_validation_options(),
) -> BatchReport {
  let reports : Array[CaseReport] = []
  let mut passed = 0
  let mut failed = 0
  for case in cases {
    let report = validate(rule, case.value, options~)
    if report.valid {
      passed += 1
    } else {
      failed += 1
    }
    reports.push({ id: case.id, report })
  }
  { valid: failed == 0, total: cases.length(), passed, failed, cases: reports }
}

///|
/// Parse a JSON array and validate every item. A non-array document produces a
/// one-case failure report.
pub fn validate_json_array(
  rule : Rule,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> BatchReport {
  let value = @json.parse(text) catch {
    _ =>
      return {
        valid: false,
        total: 1,
        passed: 0,
        failed: 1,
        cases: [{ id: "document", report: validate_json(rule, text, options~) }],
      }
  }
  match value {
    Array(values) => {
      let cases : Array[ValidationCase] = []
      for index = 0; index < values.length(); index = index + 1 {
        cases.push({ id: index.to_string(), value: values[index] })
      }
      validate_batch(rule, cases, options~)
    }
    _ => {
      let report = validate(Kind(ArrayValue), value, options~)
      {
        valid: false,
        total: 1,
        passed: 0,
        failed: 1,
        cases: [{ id: "document", report }],
      }
    }
  }
}

///|
/// Validate newline-delimited JSON. Blank lines are skipped and case ids are
/// one-based source line numbers.
pub fn validate_json_lines(
  rule : Rule,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> BatchReport {
  let cases : Array[CaseReport] = []
  let mut passed = 0
  let mut failed = 0
  let mut line_number = 0
  for raw in text.split("\n") {
    line_number += 1
    let line = raw.trim().to_owned()
    if line.is_empty() {
      continue
    }
    let report = validate_json(rule, line, options~)
    if report.valid {
      passed += 1
    } else {
      failed += 1
    }
    cases.push({ id: line_number.to_string(), report })
  }
  { valid: failed == 0, total: cases.length(), passed, failed, cases }
}

///|
fn increment_issue_count(counts : Array[IssueCount], code : String) -> Unit {
  for index = 0; index < counts.length(); index = index + 1 {
    if counts[index].code == code {
      counts[index] = { code, count: counts[index].count + 1 }
      return
    }
  }
  counts.push({ code, count: 1 })
}

///|
/// Count issue codes in one validation report.
pub fn issue_histogram(report : ValidationReport) -> Array[IssueCount] {
  let counts : Array[IssueCount] = []
  for issue in report.issues {
    increment_issue_count(counts, issue.code)
  }
  counts
}

///|
/// Count issue codes across a complete batch.
pub fn batch_issue_histogram(report : BatchReport) -> Array[IssueCount] {
  let counts : Array[IssueCount] = []
  for case in report.cases {
    for issue in case.report.issues {
      increment_issue_count(counts, issue.code)
    }
  }
  counts
}

///|
pub fn batch_to_json(report : BatchReport) -> String {
  report.to_json().stringify(indent=2)
}

///|
/// Produce a compact terminal-friendly summary.
pub fn batch_summary(report : BatchReport) -> String {
  let status = if report.valid { "PASS" } else { "FAIL" }
  "\{status}: \{report.passed}/\{report.total} passed, \{report.failed} failed"
}

///|
/// Prefix issue paths when embedding a child report in a larger API response.
pub fn prefix_report_paths(
  report : ValidationReport,
  prefix : String,
) -> ValidationReport {
  let issues = report.issues.map(issue => {
    ..issue,
    path: if issue.path.is_empty() {
      prefix
    } else {
      "\{prefix}\{issue.path}"
    },
  })
  { ..report, issues, }
}

///|
/// Merge reports while preserving issue order and summing deterministic stats.
pub fn merge_reports(reports : Array[ValidationReport]) -> ValidationReport {
  let issues : Array[ValidationIssue] = []
  let mut visits = 0
  let mut checked = 0
  let mut depth = 0
  let mut errors = 0
  let mut warnings = 0
  let mut infos = 0
  let mut truncated = false
  for report in reports {
    issues.push_iter(report.issues.iter())
    visits += report.stats.rule_visits
    checked += report.stats.values_checked
    depth = depth.max(report.stats.maximum_depth)
    errors += report.stats.error_count
    warnings += report.stats.warning_count
    infos += report.stats.info_count
    truncated = truncated || report.stats.truncated
  }
  {
    valid: errors == 0,
    issues,
    stats: {
      rule_visits: visits,
      values_checked: checked,
      maximum_depth: depth,
      error_count: errors,
      warning_count: warnings,
      info_count: infos,
      truncated,
    },
  }
}
