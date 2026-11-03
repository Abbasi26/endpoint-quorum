# Feature Specification: `-FailOnCount` Minimum Finding Threshold

## Problem Statement

`Invoke-Quorum` currently supports `-FailOnSeverity` to gate CI/CD pipelines: it writes the report and throws if any finding reaches the given severity. Teams also need a **minimum finding count** gate — for example, "fail the build if there are 10 or more high findings" or "fail if total findings reach or exceed 50" — without adding a new severity level or changing rule definitions.

## Goals

- Add a `-FailOnCount <int>` parameter to `Invoke-Quorum`.
- When **both** `-FailOnSeverity` and `-FailOnCount` are provided: count only findings at that severity or worse; throw if count ≥ threshold. The count gate owns the throw and the standalone `-FailOnSeverity` throw is suppressed.
- When **only** `-FailOnCount` is provided: count **all** findings regardless of severity; throw if count ≥ threshold.
- Behavior mirrors `-FailOnSeverity`: write the report first, then throw with a message that includes the count, the threshold, and the report path.
- The result object already carries `FindingCount` and `HighestSeverity`; no new result properties required.
- Keep the change small (< 300 lines diff), single PR, no new dependencies.

## Non-Goals

- No new output formats, no new collectors, no rule changes.
- No percentage-based thresholds, no per-rule thresholds, no time-window thresholds.
- No changes to `Test-QuorumRule`.
- No changes to the HTML/Markdown/CSV/JSON report content.

## Proposed Architecture

The `-FailOnCount` parameter adds a post-evaluation gate in `Invoke-Quorum`:

1. Rules evaluate and materialize the findings array in `$model['findings']`.
2. `New-QuorumReport` writes the report (HTML/Markdown/CSV/JSON) and returns `$written` with `HtmlPath`.
3. The new gate runs: if `-FailOnCount` is set, count findings (all, or filtered by `-FailOnSeverity` via `Get-QuorumSeverityRank`), compare to threshold, throw if `count ≥ threshold` with message including count, threshold, and report path.
4. No new collectors, output formats, rules, or result properties — ecosystem integration is unchanged.

## User Behavior

```powershell
# Fail if 10 or more high-or-worse findings (demo has 18 high, measured with Invoke-Quorum -Demo)
Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 10
# throws: "Quorum found 18 finding(s) at severity high or worse. Threshold: 10. The report was written to ..."

# Fail if 39 or more total findings (demo has 39, measured with Invoke-Quorum -Demo)
Invoke-Quorum -Demo -FailOnCount 39
# throws: "Quorum found 39 total finding(s). Threshold: 39. The report was written to ..."

# Pass: threshold is above the actual count
Invoke-Quorum -Demo -FailOnCount 50
# returns result, no throw

# Pass: no findings reach severity
Invoke-Quorum -Demo -FailOnSeverity critical -FailOnCount 1
# returns result, no throw
```

Error message format (mirrors `-FailOnSeverity` style):

- With severity: `Quorum found {N} finding(s) at severity {X} or worse. Threshold: {C}. The report was written to {PATH}.`
- Without severity: `Quorum found {N} total finding(s). Threshold: {C}. The report was written to {PATH}.`

## Alternatives Considered

| Alternative | Rejection Rationale |
|------------|---------------------|
| Add `-FailOnHighCount`, `-FailOnMediumCount`, … per-severity parameters | Explodes parameter surface; `-FailOnSeverity` + `-FailOnCount` composes cleanly and covers all cases with two parameters. |
| Percentage threshold (e.g., `-FailOnPercent 20`) | Requires a denominator (devices? findings?); ambiguous. Count is explicit and matches pipeline gating patterns. |
| Fail during evaluation (before report) | Current `-FailOnSeverity` writes the report before throwing, so operators always have the artifact; an early exit would require a separate report-write path. |
| New result property `ExceededThreshold` | Redundant — the throw is the gate. Callers can catch and inspect `$_.Exception.Message` if needed. |
| Implement as a rule condition | Rules evaluate per-device; a count gate is a post-evaluation policy decision, not a per-device fact. |

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Parameter validation edge cases (negative count, zero) | Validate `-FailOnCount` ≥ 1; throw a parameter-binding error naming `-FailOnCount` and requiring a value ≥ 1. |
| Interaction with `-FailOnSeverity` when severity is `info` (all findings count) | Documented behavior: `info` includes everything, same as no severity filter. Acceptance criterion covers this (see AC #8). |
| When both `-FailOnSeverity` and `-FailOnCount` are set, the count gate must own the throw and the standalone `-FailOnSeverity` throw must be suppressed; otherwise AC #3/#4/#8 and combined-mode tests fail. | Specify precedence explicitly in Goals and Implementation Plan; gate the existing `-FailOnSeverity` block with `if ($FailOnSeverity -and -not $FailOnCount)`. |
| Future parameter additions before `-FailOnCount` could shift its implicit position | Do not rely on positional binding in documentation/examples; use named parameters. |
| Performance on large inventories | Counting is O(n) over the already-materialized findings array; negligible. |
| Confusion between "threshold" and "limit" | Use "Threshold" in messages and help text consistently. |

## Acceptance Criteria

1. `Invoke-Quorum -Demo -FailOnCount 39` throws; report exists.
2. `Invoke-Quorum -Demo -FailOnCount 40` returns result; no throw.
3. `Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 10` throws (18 high findings); report exists.
4. `Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 20` returns result; no throw.
5. `Invoke-Quorum -Demo -FailOnSeverity critical -FailOnCount 1` returns result; no throw.
6. `Invoke-Quorum -Demo -FailOnCount 0` throws parameter validation error.
7. `Invoke-Quorum -Demo -FailOnCount -5` throws parameter validation error.
8. `Invoke-Quorum -Demo -FailOnSeverity info -FailOnCount 39` throws (39 total findings); report exists.
9. Help text (`Get-Help Invoke-Quorum -Parameter FailOnCount`) documents the two modes.
10. README "Gate a scheduled run" section updated with examples.
11. CHANGELOG.md updated under "Unreleased".
12. ROADMAP.md "Good first issues" row for `-FailOnCount` checked off.
13. All existing Pester tests pass; new tests in `tests/V02Features.Tests.ps1` cover the 8 behavioral cases above (criteria 1–8) plus the help-text verification (criterion 9).

---

## Detailed Implementation Plan

### Affected Files & Functions

| File | Change Type |
|------|-------------|
| `Public/Invoke-Quorum.ps1` | Modify: parameter block, validation, gating logic, help |
| `tests/V02Features.Tests.ps1` | Add: new `Describe 'FailOnCount'` block with 8 tests |
| `README.md` | Modify: "Gate a scheduled run" section |
| `CHANGELOG.md` | Modify: add entry under "Unreleased" |
| `ROADMAP.md` | Modify: check off the `-FailOnCount` row |

### Parameter Signature

```powershell
[ValidateRange(1, 2147483647)]
[int]$FailOnCount
```

- Placed after `-FailOnSeverity` in the param block for logical grouping (note: this sits before the URI parameter group; named binding is recommended).
- `ValidateRange` ensures ≥ 1; zero/negative rejected by PowerShell with a standard parameter-binding error naming `-FailOnCount` and requiring a value ≥ 1.

### Logic Changes in `Invoke-Quorum`

**Location**: After `$result` object is constructed (line ~289). The existing `-FailOnSeverity` block (lines 305–311) must be gated so it only runs when `-FailOnCount` is **not** set.

**Pseudocode**:

```powershell
# Existing -FailOnSeverity block — now gated to run only when -FailOnCount is NOT set
if ($FailOnSeverity -and -not $FailOnCount) {
    $limit = Get-QuorumSeverityRank $FailOnSeverity
    $over = @($model['findings'] | Where-Object { (Get-QuorumSeverityRank ([string]$_['severity'])) -le $limit })
    if ($over.Count -gt 0) {
        $msg = "Quorum found {0} finding(s) at severity {1} or worse. The report was written to {2}." -f $over.Count, $FailOnSeverity, $written.HtmlPath
        throw $msg
    }
}

# New -FailOnCount gate (runs after report is written)
if ($FailOnCount) {
    if ($FailOnSeverity) {
        $severityLimit = Get-QuorumSeverityRank $FailOnSeverity
        $over = @($model['findings'] | Where-Object { (Get-QuorumSeverityRank ([string]$_['severity'])) -le $severityLimit })
        $msg = "Quorum found {0} finding(s) at severity {1} or worse. Threshold: {2}. The report was written to {3}." -f $over.Count, $FailOnSeverity, $FailOnCount, $written.HtmlPath
    }
    else {
        $over = @($model['findings'])
        $msg = "Quorum found {0} total finding(s). Threshold: {1}. The report was written to {2}." -f $over.Count, $FailOnCount, $written.HtmlPath
    }
    if ($over.Count -ge $FailOnCount) {
        throw $msg
    }
}
```

- Uses existing `Get-QuorumSeverityRank` (lower rank = worse severity); variable renamed to `$severityLimit` for clarity.
- `$model['findings']` is already the evaluated findings array; `$written` is returned by `New-QuorumReport` (line ~275).
- Throws **after** report is written (same position as `-FailOnSeverity`); message wording differs by adding the threshold.
- Does not mutate `$result`; the throw prevents return.
- When both parameters are set, the count gate owns the throw and the standalone `-FailOnSeverity` throw is suppressed.

### Help Text for `-FailOnCount`

```powershell
.PARAMETER FailOnCount
    After the report is written, throw if the number of findings reaches this threshold.
    With -FailOnSeverity: counts only findings at that severity or worse.
    Without -FailOnSeverity: counts all findings.
    Use it in scheduled tasks and pipelines. Named binding recommended.
```

### Test Cases (Pester)

Add a new `Describe 'FailOnCount'` block in `tests/V02Features.Tests.ps1`:

```powershell
Describe 'FailOnCount' {
    It 'throws when total findings reach the threshold' {
        $out = Join-Path $script:Work 'cnt1'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnCount 39 6>$null } | Should -Throw '*total finding(s)*Threshold: 39*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'passes when total findings are below the threshold' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'cnt2') -FailOnCount 40 6>$null
        $r.FindingCount | Should -Be 39
    }

    It 'throws when findings at severity reach the threshold' {
        $out = Join-Path $script:Work 'cnt3'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnSeverity high -FailOnCount 10 6>$null } | Should -Throw '*severity high or worse*Threshold: 10*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'passes when findings at severity are below the threshold' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'cnt4') -FailOnSeverity high -FailOnCount 20 6>$null
        $r.FindingCount | Should -Be 39
    }

    It 'passes when no finding reaches the severity' {
        $r = Invoke-Quorum -Demo -OutputPath (Join-Path $script:Work 'cnt5') -FailOnSeverity critical -FailOnCount 1 6>$null
        $r.FindingCount | Should -Be 39
    }

    It 'rejects zero threshold' {
        { Invoke-Quorum -Demo -FailOnCount 0 -OutputPath (Join-Path $script:Work 'cnt6') 6>$null } | Should -Throw
    }

    It 'rejects negative threshold' {
        { Invoke-Quorum -Demo -FailOnCount -5 -OutputPath (Join-Path $script:Work 'cnt7') 6>$null } | Should -Throw
    }

    It 'works with info severity (counts all)' {
        $out = Join-Path $script:Work 'cnt8'
        { Invoke-Quorum -Demo -OutputPath $out -FailOnSeverity info -FailOnCount 39 6>$null } | Should -Throw '*severity info or worse*Threshold: 39*'
        Test-Path -LiteralPath (Join-Path $out 'Quorum-Report.html') | Should -BeTrue
    }

    It 'help text documents the parameter' {
        (Get-Help Invoke-Quorum -Parameter FailOnCount).description.Text | Should -Match 'reaches this threshold'
    }
}
```

- All tests use the demo inventory (39 findings, 18 high; measured with `Invoke-Quorum -Demo` on `data/demo-inventory.json`).
- `6>$null` suppresses information stream (Write-Host) for clean test output.
- The throw-on-threshold tests verify the report file exists; the validation tests throw before a report is written.
- A help-text verification test covers criterion 9 (AC #9).

### Documentation Changes

**README.md** — "Gate a scheduled run" section (lines 84–91). Insert the following block (lines 214–227 only; do not copy the outer ```markdown fence):

```markdown
## Gate a scheduled run

`-FailOnSeverity` writes the report first and then throws if any finding is at that severity or worse. The result object also carries `HighestSeverity`.

`-FailOnCount` fails the run when the finding count reaches this threshold. With `-FailOnSeverity` it counts only findings at that severity or worse; alone it counts all findings.

```powershell
Invoke-Quorum -Demo -FailOnSeverity high      # throws: the demo has high findings
Invoke-Quorum -Demo -FailOnSeverity critical  # passes
Invoke-Quorum -Demo -FailOnCount 39           # throws: demo has 39 total findings
Invoke-Quorum -Demo -FailOnCount 40           # passes
Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 10  # throws: 18 high >= 10
Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 20  # passes
```
```

**CHANGELOG.md** — under "Unreleased":

```markdown
- `-FailOnCount` parameter for `Invoke-Quorum`: throws after the report is written when the finding count reaches a threshold. With `-FailOnSeverity` counts only findings at that severity or worse; alone counts all findings.
```

**ROADMAP.md** — check off the row in the "Good first issues" table (3 columns: Idea, Where to start, Test). The row for `-FailOnCount` currently has three cells; add a check mark in the Test column or append a status note per the table's convention:

```markdown
| `-FailOnSeverity` also accepts a minimum finding count (`-FailOnCount`) | `Public/Invoke-Quorum.ps1` | demo run with a threshold above and below 36 ✅ |
```

### Verification Steps

1. Run `Invoke-Pester ./tests` — all tests pass.
2. Manual demo runs:
   - `Invoke-Quorum -Demo -FailOnCount 39` → throws, report exists
   - `Invoke-Quorum -Demo -FailOnCount 40` → returns, no throw
   - `Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 10` → throws
   - `Invoke-Quorum -Demo -FailOnSeverity high -FailOnCount 20` → returns
3. `Get-Help Invoke-Quorum -Parameter FailOnCount` shows correct help.
4. README renders correctly on GitHub (no stray fences).
5. No new analyzer warnings (`Invoke-ScriptAnalyzer`).
## Spec amendment (2026-11-03, after implementation)

The demo numbers above were first taken from `README.md` (36 findings, 15 high). That text predates rule Q013:
the current demo run (`Invoke-Quorum -Demo`, verified with Pester on this branch) writes 39 findings, 18 of them high.
All thresholds and expected counts in this spec were updated to 39/40 and 18. The mechanism, parameters and
acceptance criteria are unchanged. The ROADMAP row text ("above and below 36") is quoted verbatim and left as is.
The README hero image alt text still describes the older 36-finding screenshot; refreshing it is out of scope.
