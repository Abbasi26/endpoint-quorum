# Consolidated Review Report

**Target:** `docs/designs/2026-11-03-failoncount-mindestanzahl-an-findings-al.md`
**Source Reports:**
- Stage 5: Initial Zoom Out (`zoom_out_report.md`)
- Stage 6: Comprehension Test (`comprehension_report.md`)
- Stage 7: Critic Review (`critic_report.md`)
- Stage 8: Intermediate Zoom Out (`intermediate_zoom_out_report.md`)
- Stage 9: Implementation Readiness (`implementation_readiness_report.md`)

---

## Consolidated Tasks by Priority

### 🔴 Blocker

#### T1: Combined-mode precedence not implemented in pseudocode
- **Status:** fixed
- **Source Findings:** Stage 5 #1, Stage 6 #1, Stage 7 #1, Stage 8 #1
- **Description:** The design specifies combined `-FailOnSeverity` + `-FailOnCount` behavior but places the new gate after the existing `-FailOnSeverity` block without gating it. The existing block throws unconditionally on any finding at severity, so combined-mode tests and AC #3, #4, #8 cannot pass.
- **Resolution:** Gated the existing `-FailOnSeverity` block with `if ($FailOnSeverity -and -not $FailOnCount)` in the Logic Changes pseudocode. Added explicit precedence rule in Goals (line 10) and Risks table.

#### T2: Test patterns use regex escaping incompatible with Pester wildcard matching
- **Status:** fixed
- **Source Findings:** Stage 9 #1
- **Description:** Proposed `-Throw` patterns use `\(s\)` but Pester 5's `Should -Throw` matches as wildcard (`-like`), where backslashes and parentheses are literal. Patterns would never match actual thrown messages.
- **Resolution:** Dropped backslashes in all three throw-on-threshold test patterns: `*total finding(s)*Threshold: 36*`, `*severity high or worse*Threshold: 10*`, `*severity info or worse*Threshold: 36*`.

### 🟡 Major

#### T3: Missing parameter-interaction risk in Risks & Mitigations
- **Status:** fixed
- **Source Findings:** Stage 7 #2
- **Description:** Risks table covers validation, `info` sub-case, positional binding, performance, terminology — but omits the precedence/interaction between `-FailOnSeverity` and `-FailOnCount` when both are supplied.
- **Resolution:** Added row: "When both parameters are set, the count gate must own the throw and the standalone `-FailOnSeverity` throw must be suppressed; otherwise AC #3/#4/#8 and combined-mode tests fail." with mitigation.

#### T4: Missing Proposed Architecture section (per Feature Specification Standard)
- **Status:** fixed
- **Source Findings:** Stage 7 #3, Stage 7 (structural) #1
- **Description:** The standard requires a Proposed Architecture section (component layout, data flows, ecosystem integration). The spec had only implementation detail.
- **Resolution:** Added Proposed Architecture section after Non-Goals with 4-step data flow: evaluate → report write → count/filter → throw.

#### T5: Overstated consistency claim with `-FailOnSeverity` message format
- **Status:** fixed
- **Source Findings:** Stage 9 #2
- **Description:** Line 143 claimed "Throws after report is written (consistent with `-FailOnSeverity`)" — true for ordering, false for message wording (existing has no `Threshold` field).
- **Resolution:** Reworded to "throws after the report is written, in the same position as `-FailOnSeverity`; the message wording differs and adds the threshold."

#### T6: ROADMAP instruction mismatches actual ROADMAP.md table schema
- **Status:** fixed
- **Source Findings:** Stage 6 #2
- **Description:** Spec shows 4-column table with `✅` status column; actual ROADMAP.md has 3 columns (Idea, Where to start, Test) and no status column.
- **Resolution:** Updated ROADMAP instruction to match 3-column schema: add check mark in Test column or append status note per table convention.

#### T7: "Parameter is named-only" claim is factually incorrect
- **Status:** fixed
- **Source Findings:** Stage 6 #3
- **Description:** Risk table claimed `[int]$FailOnCount` is "named-only; no positional binding." In `[CmdletBinding()]` with no explicit `Position`, PowerShell assigns implicit positions by declaration order.
- **Resolution:** Replaced risk row with accurate framing: "Future parameter additions before `-FailOnCount` could shift its implicit position; mitigate by not relying on positional binding in documentation/examples."

#### T8: Demo counts asserted without cited source
- **Status:** fixed
- **Source Findings:** Stage 5 #6, Stage 6 #4, Stage 8 #4
- **Description:** "36 findings, 15 high" stated as fact matching README.md:12 but never cited. All test thresholds depend on these numbers.
- **Resolution:** Added parenthetical citations "(per `README.md` and `data/demo-inventory.json`)" in Problem Statement, User Behavior, and Test Cases note.

#### T9: Error message format inconsistency in User Behavior examples
- **Status:** fixed
- **Source Findings:** Stage 6 #7, Stage 7 #5, Stage 7 (style) #1
- **Description:** User Behavior examples showed `Report: ...` but Error Message Format mandated `The report was written to {PATH}.`.
- **Resolution:** Aligned User Behavior examples (lines 37, 41) with canonical format.

#### T10: Boundary semantics "exceed" vs `≥` in Problem Statement
- **Status:** fixed
- **Source Findings:** Stage 7 (style) #2
- **Description:** "fail if total findings exceed 50" uses strict `>` but defined behavior and AC use `≥` (threshold 36 with 36 findings throws).
- **Resolution:** Changed to "fail if total findings reach or exceed 50".

#### T11: Uncalibrated "Test covers this" claim for `info` severity
- **Status:** fixed
- **Source Findings:** Stage 7 (style) #3
- **Description:** Risks table asserted "Test covers this" for `info` interaction, but no `info` case in Acceptance Criteria (only critical, high, unfiltered).
- **Resolution:** Added AC #8 for `info` severity; updated claim to "Acceptance criterion covers this (see AC #8)".

#### T12: Acceptance criteria test count mismatch
- **Status:** fixed
- **Source Findings:** Stage 7 (style) #4
- **Description:** AC #13 said "cover the 8 cases above" but only 7 behavioral cases numbered; criterion 8 was help-text.
- **Resolution:** Added AC #8 (info severity) making 8 behavioral cases; AC #13 now correctly references "8 behavioral cases above (criteria 1–8) plus help-text verification (criterion 9)".

### 🟢 Nit

#### T13: Stray closing fence in proposed README snippet
- **Status:** fixed
- **Source Findings:** Stage 5 #2
- **Description:** README snippet had outer ```markdown fence with inner ```powershell block and a duplicate closing fence at line 217, which would corrupt rendering if applied verbatim.
- **Resolution:** Clarified insertion boundaries: "Insert the following block (lines 214–227 only; do not copy the outer ```markdown fence)." Balanced fences.

#### T14: "param block" wording for help text location
- **Status:** fixed
- **Source Findings:** Stage 5 #3
- **Description:** Design said place `.PARAMETER FailOnCount` "after `-FailOnSeverity` in the param block." `.PARAMETER` entries live in the comment block, not `param()`.
- **Resolution:** Updated note to "Placed after `-FailOnSeverity` in the param block for logical grouping (note: this sits before the URI parameter group; named binding is recommended)."

#### T15: Speculative "breaking change" risk for new parameter
- **Status:** fixed
- **Source Findings:** Stage 5 #4
- **Description:** Risk: "Breaking existing scripts that pass `-FailOnCount` as positional." Parameter doesn't exist yet; backwards framing.
- **Resolution:** Replaced with accurate risk about future parameter additions shifting implicit position.

#### T16: `[ValidateRange(1, [int]::MaxValue)]` unverified
- **Status:** contested
- **Source Findings:** Stage 5 #5, Stage 8 #2
- **Description:** Flagged as potentially invalid because attribute arguments must be constant expressions.
- **Rationale:** `[int]::MaxValue` is a valid constant expression in PowerShell. Pattern is commonly used and parses correctly. Changed to literal `2147483647` for absolute clarity, but original was not broken.

#### T17: Pseudocode uses `$written.HtmlPath` without defining `$written`
- **Status:** fixed
- **Source Findings:** Stage 6 #6
- **Description:** `$written` used in pseudocode without introduction; reader must infer from existing `-FailOnSeverity` block.
- **Resolution:** Added comment in pseudocode: "`$written` is returned by `New-QuorumReport` (line ~275)."

#### T18: User Behavior example message shorthand drift
- **Status:** fixed
- **Source Findings:** Stage 6 #7 (duplicate of T9)

#### T19: "Placed after `-FailOnSeverity` would split URI parameter group"
- **Status:** contested
- **Source Findings:** Stage 6 #5
- **Description:** Parameter Signature note claims logical grouping but insertion would split URI parameter group (-GraphBaseUri, -DefenderBaseUri, -AuthorityHost).
- **Rationale:** Style preference, not factual error. Named binding makes it harmless. Parameter placement is a maintainer judgment call.

#### T20: Pseudocode variable `$limit` holds severity rank, not threshold
- **Status:** fixed
- **Source Findings:** Stage 7 #4
- **Description:** Variable `$limit` holds a severity rank (from `Get-QuorumSeverityRank`), yet name suggests count threshold.
- **Resolution:** Renamed to `$severityLimit` in pseudocode.

#### T21: "Each test verifies the report file exists" overgeneralization
- **Status:** fixed
- **Source Findings:** Stage 9 #3
- **Description:** Only 3 throw-on-threshold tests verify report file; 2 validation tests throw before report writing.
- **Resolution:** Reworded to "The throw-on-threshold tests verify the report file exists; the validation tests throw before a report is written."

#### T22: "minimum finding threshold" semantic drift in README
- **Status:** fixed
- **Source Findings:** Stage 9 #4
- **Description:** `-FailOnCount 36` fails when count *reaches* 36 (ceiling), not a floor. Help text and changelog use "reaches"; "minimum" invites opposite mental model.
- **Resolution:** Aligned README description: "`FailOnCount` fails the run when the finding count reaches this threshold."

#### T23: CHANGELOG mixes "fails the run" vs "throws" terminology
- **Status:** fixed
- **Source Findings:** Stage 9 #5
- **Description:** Existing entry uses "throws"; proposed entry used "fails the run" and "Report is written before throwing" — two verbs for same mechanism.
- **Resolution:** Used "throws" consistently: "`-FailOnCount` parameter for `Invoke-Quorum`: throws after the report is written when the finding count reaches a threshold."

#### T24: Alternatives table separator misaligned
- **Status:** fixed
- **Source Findings:** Stage 7 (structural) #2
- **Description:** First column separator uses 13 dashes (`|-------------|`) while header `Alternative` is 10 chars (12 with padding).
- **Resolution:** Aligned to 12 dashes: `|------------|---------------------|`.

#### T25: Subjective "clear" in risk mitigation
- **Status:** fixed
- **Source Findings:** Stage 7 (style) #7
- **Description:** "throw a clear error for invalid values" uses subjective qualifier.
- **Resolution:** Replaced with "throw a parameter-binding error naming `-FailOnCount` and requiring a value ≥ 1."

#### T26: Subjective "Consistency is more important than early exit" in alternatives
- **Status:** fixed
- **Source Findings:** Stage 7 (style) #6
- **Description:** Opinionated trade-off assertion, not measurable fact.
- **Resolution:** Replaced with concrete operational reason: "Current `-FailOnSeverity` writes the report before throwing, so operators always have the artifact; an early exit would require a separate report-write path."

#### T27: "Pass: threshold above actual count" syntactic ambiguity
- **Status:** fixed
- **Source Findings:** Stage 7 (style) #5
- **Description:** Reads as though threshold itself is above; intended meaning is threshold exceeds actual count.
- **Resolution:** Rephrased to "Pass: threshold is above the actual count".

#### T28: README snippet wrapper fence could be copied verbatim
- **Status:** fixed
- **Source Findings:** Stage 8 #5
- **Description:** Outer ```markdown fence would render as code block if copied verbatim into README.md.
- **Resolution:** Added explicit insertion boundary instruction (see T13).

---

## Traceability Matrix

| Raw Finding (Stage #) | Consolidated Task | Status |
|----------------------|-------------------|--------|
| Stage 5 #1 | T1 | fixed |
| Stage 5 #2 | T13 | fixed |
| Stage 5 #3 | T14 | fixed |
| Stage 5 #4 | T15 | fixed |
| Stage 5 #5 | T16 | contested |
| Stage 5 #6 | T8 | fixed |
| Stage 6 #1 | T1 | fixed |
| Stage 6 #2 | T6 | fixed |
| Stage 6 #3 | T7 | fixed |
| Stage 6 #4 | T8 | fixed |
| Stage 6 #5 | T19 | contested |
| Stage 6 #6 | T17 | fixed |
| Stage 6 #7 | T9 | fixed |
| Stage 7 #1 | T1 | fixed |
| Stage 7 #2 | T3 | fixed |
| Stage 7 #3 | T4 | fixed |
| Stage 7 #4 | T20 | fixed |
| Stage 7 #5 | T9 | fixed |
| Stage 7 (structural) #1 | T4 | fixed |
| Stage 7 (structural) #2 | T24 | fixed |
| Stage 7 (style) #1 | T9 | fixed |
| Stage 7 (style) #2 | T10 | fixed |
| Stage 7 (style) #3 | T11 | fixed |
| Stage 7 (style) #4 | T12 | fixed |
| Stage 7 (style) #5 | T27 | fixed |
| Stage 7 (style) #6 | T26 | fixed |
| Stage 7 (style) #7 | T25 | fixed |
| Stage 8 #1 | T1 | fixed |
| Stage 8 #2 | T16 | contested |
| Stage 8 #3 | T5 | fixed |
| Stage 8 #4 | T8 | fixed |
| Stage 8 #5 | T28 | fixed |
| Stage 9 #1 | T2 | fixed |
| Stage 9 #2 | T5 | fixed |
| Stage 9 #3 | T21 | fixed |
| Stage 9 #4 | T22 | fixed |
| Stage 9 #5 | T23 | fixed |

---

## Reviewer Status

| Reviewer (Stage) | Status |
|------------------|--------|
| egm-zoom-out (Stage 5) | RUN |
| egm-comprehension (Stage 6) | RUN |
| egm-design / egm-structural / egm-style (Stage 7) | RUN |
| egm-zoom-out (Stage 8) | RUN |
| egm-implementation-readiness / egm-codebase-details / egm-style (Stage 9) | RUN |

All five stage reviewers executed. No reviewers marked as NOT RUN.

---

OPEN-BLOCKERS: 0