# Goldfish Annotated Review Report

**Target:** `docs/designs/2026-11-03-failoncount-mindestanzahl-an-findings-al.md` (lines 1–84, Feature-Teil)

## Prioritized Findings & AI Suggestions

### F1 [egm-zoom-out / egm-comprehension / egm-design] - Severity: Blocker
*   **Affected Scope:** Goals (line 10), User Behavior (lines 27–28), Acceptance Criteria (lines 72–74, AC #3, #4, #8)
*   **Discrepancy:** The design defines combined `-FailOnSeverity` + `-FailOnCount` mode but places the new gate *after* the existing `-FailOnSeverity` block, which throws unconditionally on any finding at that severity. The existing block's message lacks the `Threshold:` token, so AC #3, #4, #8 and tests `cnt3`/`cnt4`/`cnt8` cannot pass as written.
*   **Rationale:** The spec's own User Behavior example (line 28) promises a `Threshold: 10` message, confirming intent — the plan is wrong, not the intent. The existing `-FailOnSeverity` block must be gated/suppressed when `-FailOnCount` is present.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The contradiction between the specified combined-mode behavior and the unimplemented modification to the existing block makes the design unimplementable as written. The fix must be documented in the Feature-Teil (Goals/User Behavior/Acceptance Criteria) to state the precedence rule explicitly.
*   ***Proposed Edit:***
    *   Location: Goals (line 10), User Behavior (lines 27–28), Acceptance Criteria (lines 72–74)
    *   Change: Add explicit precedence rule: "When both `-FailOnSeverity` and `-FailOnCount` are provided, the count gate owns the throw and the standalone `-FailOnSeverity` throw is suppressed." Update AC #3, #4, #8 to reflect this.

### F2 [egm-zoom-out / egm-comprehension] - Severity: Major
*   **Affected Scope:** Risks & Mitigations (line 64), Parameter Signature (line 100–102, but referenced in Feature-Teil)
*   **Discrepancy:** The risk table claims "Parameter is named-only (`[int]$FailOnCount`); no positional binding." In a `[CmdletBinding()]` function with no explicit `Position` attributes, PowerShell assigns implicit positions by declaration order — so a plain `[int]$FailOnCount` **would** be positionally bindable.
*   **Rationale:** The mitigation leans on a false property. The real risk framing ("breaking scripts that pass `-FailOnCount` positionally") is backwards since the parameter cannot have existed before.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The claim is factually incorrect about PowerShell parameter binding semantics. The risk row should be corrected or removed.
*   ***Proposed Edit:***
    *   Location: Risks & Mitigations, line 64
    *   Change: Replace the row with accurate risk: "Parameter binding order may change if new parameters are added before `-FailOnCount`" or remove the row entirely since it's not a real risk for a new parameter.

### F3 [egm-zoom-out / egm-comprehension / egm-design] - Severity: Major
*   **Affected Scope:** Problem Statement (line 5), User Behavior (line 27), Test Cases (lines 152, 194 — outside scope but rooted here)
*   **Discrepancy:** "36 findings, 15 high" is stated as fact matching `README.md:12`, but the design never cites the source. All test thresholds depend on these numbers; if the demo drifts, tests fail silently.
*   **Rationale:** A fresh reader cannot verify the counts from the document alone.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The demo counts are load-bearing for all thresholds. Citing the source (`README.md` / `data/demo-inventory.json`) makes the dependency explicit and verifiable.
*   ***Proposed Edit:***
    *   Location: Problem Statement (line 5), User Behavior (line 27)
    *   Change: Add parenthetical citation: "(per `README.md` and `data/demo-inventory.json`)".

### F4 [egm-design] - Severity: Major
*   **Affected Scope:** Risks & Mitigations (lines 58–66)
*   **Discrepancy:** The risks table covers validation edge cases, `info` sub-case, positional binding, performance, and terminology — but never the precedence/interaction between `-FailOnSeverity` and `-FailOnCount` when both are supplied. That is precisely the gap that produces Finding F1.
*   **Rationale:** The missing interaction risk is the root cause of the Blocker.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The risks table must include the parameter-interaction risk to be complete per the standard.
*   ***Proposed Edit:***
    *   Location: Risks & Mitigations table (after line 66)
    *   Change: Add row: "When both parameters are set, the count gate must own the throw and the standalone `-FailOnSeverity` throw must be suppressed; otherwise AC #3/#4/#8 and combined-mode tests fail." | "Specify precedence explicitly in Goals and Implementation Plan; gate the existing `-FailOnSeverity` block with `if ($FailOnSeverity -and -not $FailOnCount)`."

### F5 [egm-structural / egm-design] - Severity: Major
*   **Affected Scope:** Lines 1–84 (Feature-Teil)
*   **Discrepancy:** The Feature Specification Standard lists **Proposed Architecture** (component layout, data flows, ecosystem integration) as a mandatory area. The target spec contains no such section in the audited range.
*   **Rationale:** A fresh reader cannot see how the new `-FailOnCount` parameter fits into the existing `Invoke-Quorum` flow at the architecture level.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Mandatory section per the standard. Adding a short architecture/data-flow paragraph satisfies compliance.
*   ***Proposed Edit:***
    *   Location: After `## Non-Goals` (line 22), before `## User Behavior` (line 23)
    *   Change: Insert new section:
        ```markdown
        ## Proposed Architecture
        
        The `-FailOnCount` parameter adds a post-evaluation gate in `Invoke-Quorum`:
        1. Rules evaluate and materialize the findings array in `$model['findings']`.
        2. `New-QuorumReport` writes the report (HTML/Markdown/CSV/JSON) and returns `$written` with `HtmlPath`.
        3. The new gate runs: if `-FailOnCount` is set, count findings (all, or filtered by `-FailOnSeverity` via `Get-QuorumSeverityRank`), compare to threshold, throw if `count ≥ threshold` with message including count, threshold, and report path.
        4. No new collectors, output formats, rules, or result properties — ecosystem integration is unchanged.
        ```

### F6 [egm-style / egm-zoom-out / egm-comprehension / egm-design] - Severity: Major
*   **Affected Scope:** User Behavior (lines 28, 32) vs. Error message format (lines 45–46)
*   **Discrepancy:** The worked examples show the throw message ending in `Report: ...` (lines 28, 32), but the format specification two sections later mandates `The report was written to {PATH}.` (lines 45–46). Both are presented as the actual thrown text.
*   **Rationale:** An implementer reading only the examples would ship a different message than the spec defines.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The canonical format (lines 45–46) is the authoritative definition; the examples must match it exactly.
*   ***Proposed Edit:***
    *   Location: User Behavior, lines 28 and 32
    *   Change: Replace `Report: ...` with `The report was written to ...` to match lines 45–46.

### F7 [egm-style] - Severity: Major
*   **Affected Scope:** Problem Statement (line 5)
*   **Discrepancy:** The example `"fail if total findings exceed 50"` uses strict `>` semantics, but the defined behavior (lines 10–11: "throw if count ≥ threshold") and acceptance criteria (lines 70–71: threshold 36 with 36 findings throws) establish `≥`.
*   **Rationale:** At the boundary (exactly 50 findings, threshold 50) the two readings disagree.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The wording must match the `≥` gate semantics used everywhere else in the spec.
*   ***Proposed Edit:***
    *   Location: Problem Statement, line 5
    *   Change: Replace `"fail if total findings exceed 50"` with `"fail if total findings reach or exceed 50"` (or `"fail if total findings are 50 or more"`).

### F8 [egm-style] - Severity: Major
*   **Affected Scope:** Risks & Mitigations (line 63)
*   **Discrepancy:** The mitigation asserts "Test covers this" for the `info` severity interaction, but no corresponding case appears in the Acceptance Criteria (lines 70–76): numbered cases are `critical`, `high`, and unfiltered — no `info` case.
*   **Rationale:** Claims about tested behavior must match their evidence per the audit standard.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Either add an `info` acceptance case or delete the uncalibrated assertion.
*   ***Proposed Edit:***
    *   Location: Risks & Mitigations, line 63
    *   Change: Replace "Test covers this" with "Acceptance criterion covers this (see AC #8)" after adding AC #8 for `info` severity, OR delete the assertion until the test exists. Recommended: add AC for `info` and update the claim.

### F9 [egm-zoom-out] - Severity: Nit
*   **Affected Scope:** Risks & Mitigations (line 64)
*   **Discrepancy:** "Breaking existing scripts that pass `-FailOnCount` as positional." The parameter does not exist yet, so nothing can already pass it; and a `[int]$FailOnCount` is named-only by default (though see F2 — it's actually implicitly positional).
*   **Rationale:** Not a real risk for a new parameter. The risk is backwards.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The risk is speculative and incorrectly framed. Remove or reframe.
*   ***Proposed Edit:***
    *   Location: Risks & Mitigations, line 64
    *   Change: Remove the row entirely (covered by F2 correction), or replace with: "Future parameter additions before `-FailOnCount` could shift its implicit position; mitigate by not relying on positional binding in documentation/examples."

### F10 [egm-structural] - Severity: Nit
*   **Affected Scope:** Alternatives Considered (line 52)
*   **Discrepancy:** The first column separator uses 13 dashes (`|-------------|`) while the header `Alternative` is 10 chars (12 with padding).
*   **Rationale:** Cosmetic only — GitHub Flavored Markdown renders correctly, but inconsistency with the Risks table (line 61: `|------|------------|`).
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Align for consistency.
*   ***Proposed Edit:***
    *   Location: Alternatives Considered table separator, line 52
    *   Change: Replace `|-------------|---------------------|` with `|------------|---------------------|` (12 dashes to match "Alternative" + padding).

### F11 [egm-style] - Severity: Nit
*   **Affected Scope:** Acceptance Criteria (line 81)
*   **Discrepancy:** "cover the 8 cases above" but only 7 behavioral cases are numbered (criteria 1–7, lines 70–76); criterion 8 is help-text documentation, not a test case.
*   **Rationale:** The count is reconcilable only if it silently includes the unlisted `info` case from line 63 — but that case is not "above" in the numbered list.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Clarify the count or enumerate the test cases explicitly.
*   ***Proposed Edit:***
    *   Location: Acceptance Criteria, line 81
    *   Change: Replace "cover the 8 cases above" with "cover the 7 behavioral cases above (criteria 1–7) plus the help-text verification (criterion 8)" or add an 8th behavioral case for `info` severity and say "cover the 8 behavioral cases above."

### F12 [egm-style] - Severity: Nit
*   **Affected Scope:** User Behavior (line 34)
*   **Discrepancy:** "Pass: threshold above actual count" reads as though the threshold itself is what's above; the intended meaning is that the threshold exceeds the actual finding count.
*   **Rationale:** Syntactic ambiguity.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Simple rephrase removes ambiguity.
*   ***Proposed Edit:***
    *   Location: User Behavior, line 34
    *   Change: Replace "Pass: threshold above actual count" with "Pass: threshold is above the actual count" (or "actual count is below threshold").

### F13 [egm-style] - Severity: Nit
*   **Affected Scope:** Alternatives Considered (line 54)
*   **Discrepancy:** "Consistency is more important than early exit" is an opinionated trade-off assertion, not a measurable fact.
*   **Rationale:** Subjective value judgment in a rejection rationale.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Replace with concrete operational reason.
*   ***Proposed Edit:***
    *   Location: Alternatives Considered, line 54
    *   Change: Replace "Consistency is more important than early exit" with "Current `-FailOnSeverity` writes the report before throwing, so operators always have the artifact; an early exit would require a separate report-write path."

### F14 [egm-style] - Severity: Nit
*   **Affected Scope:** Risks & Mitigations (line 62)
*   **Discrepancy:** "throw a clear error for invalid values" uses the subjective qualifier "clear."
*   **Rationale:** Subjective adjective in a specification.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Specify the contract instead.
*   ***Proposed Edit:***
    *   Location: Risks & Mitigations, line 62
    *   Change: Replace "throw a clear error for invalid values" with "throw a parameter-binding error naming `-FailOnCount` and requiring a value ≥ 1."

---

## Summary
- **Blocker:** 1 (F1)
- **Major:** 7 (F2–F8)
- **Nit:** 6 (F9–F14)
- **CONTEST:** 0
- **PROPOSE FIX:** 14
- **ESCALATE:** 0
- **DECLINE:** 0

All findings are categorized as **PROPOSE FIX** — each is factually correct and within the scope of the Feature-Teil. No findings are contested.

---

# Round 2: Detailed Plan

**Target:** `docs/designs/2026-11-03-failoncount-mindestanzahl-an-findings-al.md` (lines 96–251, Detailed Implementation Plan)

## Prioritized Findings & AI Suggestions

### R1 [egm-implementation-readiness / egm-zoom-out (Stage 8)] - Severity: Blocker
*   **Affected Scope:** Logic Changes pseudocode (lines 120, 124–139), Test Cases (lines 163–204)
*   **Discrepancy:** The Implementation Plan documents the combined-mode precedence in Goals/Risks but the pseudocode places the new gate after the existing `-FailOnSeverity` block without gating it. The existing block throws unconditionally, so combined-mode tests (cnt3, cnt4, cnt8) and AC #3, #4, #8 cannot pass.
*   **Rationale:** The design is internally contradictory — Goals/Risks say "suppress the severity throw," the Implementation Plan doesn't. A design must be implementable as written.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The combined-mode guard must appear in the pseudocode, not just the Risks table. The existing `-FailOnSeverity` block must be gated with `if ($FailOnSeverity -and -not $FailOnCount)`.
*   ***Proposed Edit:***
    *   Location: Logic Changes pseudocode (lines 120–139)
    *   Change: Gate the existing `-FailOnSeverity` block; rename `$limit` to `$severityLimit`; add comment about `$written` source.

### R2 [egm-implementation-readiness] - Severity: Blocker
*   **Affected Scope:** Test Cases (lines 164, 175, 199)
*   **Discrepancy:** The proposed `-Throw` patterns use regex-style escapes (`\(s\)`) but Pester 5's `Should -Throw` matches as a wildcard (`-like`), where `\` is literal and `(` `)` are literal. These patterns will never match the actual thrown messages.
*   **Rationale:** Proof is in this repo's own existing tests — `V02Features.Tests.ps1:90` uses `*severity high or worse*` (wildcard). The design's escaping convention contradicts the file it is appended to.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** This is a CI-blocking bug; all three throw-on-threshold tests would fail under Pester 5.
*   ***Proposed Edit:***
    *   Location: Test Cases, lines 164, 175, 199
    *   Change: Drop backslashes: `*total finding(s)*Threshold: 36*`, `*severity high or worse*Threshold: 10*`, `*severity info or worse*Threshold: 36*`.

### R3 [egm-implementation-readiness] - Severity: Major
*   **Affected Scope:** Logic Changes note (line 143)
*   **Discrepancy:** Claims "Throws **after** report is written (consistent with `-FailOnSeverity`)". True for ordering, false for message wording — the existing throw has no `Threshold` field; the new messages add it.
*   **Rationale:** Uncalibrated claim creates an implementation trap: an implementer copying the existing message format silently breaks the new tests.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** The claim must be calibrated to match reality.
*   ***Proposed Edit:***
    *   Location: Logic Changes, line 143
    *   Change: Reword to "throws after the report is written, in the same position as `-FailOnSeverity`; the message wording differs and adds the threshold."

### R4 [egm-zoom-out (Stage 8)] - Severity: Nit
*   **Affected Scope:** Parameter Signature (lines 110–116)
*   **Discrepancy:** `[ValidateRange(1, [int]::MaxValue)]` flagged as unverified; attribute arguments must be constant expressions.
*   **Rationale:** `[int]::MaxValue` is a valid constant expression in PowerShell. The pattern is commonly used and parses correctly. No module-load failure occurs.
*   ***AI Suggestion:*** CONTEST
*   ***Justification:*** The concern is unfounded; `[ValidateRange(1, [int]::MaxValue)]` is valid PowerShell. Changed to literal `2147483647` for absolute clarity and compatibility, but the original was not broken.

### R5 [egm-zoom-out (Stage 8)] - Severity: Nit
*   **Affected Scope:** Acceptance Criteria (line 92), Test Cases (lines 163–204)
*   **Discrepancy:** AC #13 states tests cover "8 behavioral cases plus help-text verification" but the proposed test block contained only 8 tests (no help-text test).
*   **Rationale:** The test plan over-promises; a missing help-text test would leave AC #9 unverified.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Added a 9th test for help-text verification to match the acceptance criteria.
*   ***Proposed Edit:***
    *   Location: Test Cases block
    *   Change: Add `It 'help text documents the parameter'` test using `Get-Help`.

### R6 [egm-zoom-out (Stage 8)] - Severity: Nit
*   **Affected Scope:** Test Cases note (line 193)
*   **Discrepancy:** "All tests use the demo inventory (36 findings, 15 high)" — lines 35/39 now cite the source, but this test-section note still doesn't.
*   **Rationale:** Consistency; cite the source for verifiability.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Added citation to `README.md` and `data/demo-inventory.json`.
*   ***Proposed Edit:***
    *   Location: Test Cases note
    *   Change: Append "(per `README.md` and `data/demo-inventory.json`)".

### R7 [egm-zoom-out (Stage 8)] - Severity: Nit
*   **Affected Scope:** Documentation Changes / README snippet (lines 213–228)
*   **Discrepancy:** The proposed README content is wrapped in an outer ```markdown fence with inner ```powershell block. If copied verbatim, the outer fence renders as a code block.
*   **Rationale:** AC 9/10 ("README renders correctly") is only safe if insertion boundaries are explicit.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Clarified that only lines 214–227 (the inner content) go into README.md.
*   ***Proposed Edit:***
    *   Location: Documentation Changes, README section
    *   Change: Add instruction: "Insert the following block (lines 214–227 only; do not copy the outer ```markdown fence)."

### R8 [egm-comprehension] - Severity: Nit
*   **Affected Scope:** Parameter Signature note (line 105)
*   **Discrepancy:** "Placed after `-FailOnSeverity` … for logical grouping" would split the URI parameter group (-GraphBaseUri, -DefenderBaseUri, -AuthorityHost).
*   **Rationale:** This is a style preference, not a factual error. Named binding makes it harmless. The stated rationale ("logical grouping") is debatable.
*   ***AI Suggestion:*** CONTEST
*   ***Justification:*** The parameter placement is a maintainer judgment call; the design documents the chosen location accurately. No functional impact.

### R9 [egm-comprehension] - Severity: Nit
*   **Affected Scope:** Pseudocode (lines 118, 122)
*   **Discrepancy:** `$written.HtmlPath` used without defining `$written` in the plan.
*   **Rationale:** `$written` exists in the actual function (returned by `New-QuorumReport` at line ~275). This is a self-containment gap, not an error.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Added a comment in the pseudocode noting `$written` source.
*   ***Proposed Edit:***
    *   Location: Logic Changes pseudocode
    *   Change: Add comment: "`$written` is returned by `New-QuorumReport` (line ~275)."

### R10 [egm-design] - Severity: Nit
*   **Affected Scope:** Pseudocode (line 116, now `$severityLimit`)
*   **Discrepancy:** Variable `$limit` holds a severity rank, not a count threshold — naming could mislead.
*   **Rationale:** The message correctly uses "Threshold" for the count; this is naming only.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Renamed to `$severityLimit` for clarity.
*   ***Proposed Edit:***
    *   Location: Logic Changes pseudocode
    *   Change: `$limit` → `$severityLimit`.

### R11 [egm-implementation-readiness] - Severity: Nit
*   **Affected Scope:** Test Cases note (line 207)
*   **Discrepancy:** "Each test verifies the report file exists" — only the three throw-on-threshold tests do; validation tests throw before report writing.
*   **Rationale:** False claim about the suite; hides that zero/negative thresholds are gated before report writing.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Reworded to distinguish throw-on-threshold vs validation tests.
*   ***Proposed Edit:***
    *   Location: Test Cases note
    *   Change: "The throw-on-threshold tests verify the report file exists; the validation tests throw before a report is written."

### R12 [egm-implementation-readiness] - Severity: Nit
*   **Affected Scope:** Documentation Changes / README (line 218)
*   **Discrepancy:** "minimum finding threshold" drifts from semantics — `-FailOnCount 36` fails when count *reaches* 36 (ceiling), not a floor.
*   **Rationale:** Help text (line 150) and changelog (line 233) use "reaches"; "minimum" invites opposite mental model.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Aligned README with help text: "`FailOnCount` fails the run when the finding count reaches this threshold."
*   ***Proposed Edit:***
    *   Location: Documentation Changes, README section
    *   Change: Rephrase description.

### R13 [egm-implementation-readiness] - Severity: Nit
*   **Affected Scope:** Documentation Changes / CHANGELOG (line 233)
*   **Discrepancy:** Existing entry says "`-FailOnSeverity` throws after the report is written"; proposed says "fails the run when the finding count reaches a threshold … Report is written before throwing." Two verbs for same mechanism.
*   **Rationale:** Terminology drift in the change record.
*   ***AI Suggestion:*** PROPOSE FIX
*   ***Justification:*** Use "throws" consistently.
*   ***Proposed Edit:***
    *   Location: Documentation Changes, CHANGELOG section
    *   Change: "`-FailOnCount` parameter for `Invoke-Quorum`: throws after the report is written when the finding count reaches a threshold."

---

## Round 2 Summary
- **Blocker:** 2 (R1, R2)
- **Major:** 1 (R3)
- **Nit:** 10 (R4–R13)
- **CONTEST:** 2 (R4, R8)
- **PROPOSE FIX:** 11
- **ESCALATE:** 0
- **DECLINE:** 0

All Detailed Implementation Plan findings addressed. Two nits contested (R4: ValidateRange valid; R8: parameter placement is judgment).