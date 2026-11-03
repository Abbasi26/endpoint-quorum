# Stage 7: Critic Review (FeatureRange 1..84)
### Reviewer: egm-design (Modell: `kilo/kilo-auto/free`, frischer Prozess)



I'll start by reading the required files in parallel.
Let me verify the spec's codebase assertions against the actual source before finalizing findings.
I verified the spec against the actual codebase before finalizing. Here are my findings.

## Verified-accurate references (context for the findings below)

The spec's codebase citations check out: `$result` is constructed at lines 289–304, the existing `-FailOnSeverity` block is lines 305–311, `return $result` is line 312 (`Invoke-Quorum.ps1`); the demo really yields 36 findings (test asserts `FindingCount | Should -Be 36`, line 159); README "Gate a scheduled run" is lines 84–91; `Get-QuorumSeverityRank` semantics (lower rank = worse) are consistent at lines 279 and 307; and `[ValidateRange(1, [int]::MaxValue)]` is valid PowerShell. The existing `-FailOnSeverity` throw message (line 309) is `"Quorum found {0} finding(s) at severity {1} or worse. The report was written to {2}."` — notably **it contains no "Threshold" field**.

---

## Findings

### 1. Blocker — `-FailOnSeverity` and `-FailOnCount` block ordering contradicts the spec's own acceptance criteria and tests
- **Scope:** spec lines 109, 73, 164, 188; `Public/Invoke-Quorum.ps1` line 309.
- **Discrepancy:** The spec instructs placing the new `FailOnCount` block *after* the existing `-FailOnSeverity` block (line 109: "after the existing `-FailOnSeverity` block (lines 305–311)"). But the existing `-FailOnSeverity` block throws **first** whenever any finding reaches the severity — and its message (code line 309) has no `Threshold` field. The spec's own tests require `Threshold` in the combined message:
  - Line 164: `Should -Throw '*severity high or worse*Threshold: 10*'`
  - Line 188: `Should -Throw '*severity info or worse*Threshold: 36*'`
  Placed after, these blocks never execute — `FailOnSeverity` throws first and the tests fail.
- Worse, **AC #73 (line 73)** requires `-FailOnSeverity high -FailOnCount 20` to *return, no throw* (15 high findings, threshold 20). With `-FailOnSeverity` running first, 15 high > 0 → it throws. The AC is directly unachievable under the stated placement.
- **Rationale:** The spec's intent is clear from AC 73 and tests 164/188: when **both** parameters are set, the `FailOnCount` block must own the throw (with the combined message), and the standalone `-FailOnSeverity` throw must be suppressed. The placement note at line 109 is incompatible with that intent.
- **Recommendation:** Either (a) gate the standalone `-FailOnSeverity` block with `if ($FailOnSeverity -and -not $FailOnCount)` and let the `FailOnCount` block run afterward, or (b) reorder so the combined `FailOnCount` logic runs first and short-circuits. State the precedence rule explicitly in the spec.

### 2. Major — Risks & Mitigations omits the parameter-interaction risk
- **Scope:** spec lines 58–66.
- **Discrepancy:** The risks table covers validation edge cases, the `info` sub-case, positional binding, performance, and terminology — but never the precedence/interaction between `-FailOnSeverity` and `-FailOnCount` when both are supplied. That is precisely the gap that produces Finding #1.
- **Recommendation:** Add a row: "When both parameters are set, which block throws and in what order; ensure the combined message includes the count, threshold, and report path, and that the standalone `-FailOnSeverity` throw does not fire."

### 3. Major — "Proposed Architecture" not addressed per the Target Standard
- **Scope:** spec lines 85–143; `feature-spec-standard.md` line 35.
- **Discrepancy:** The standard requires the spec to detail "Proposed Architecture: Component layout, data flows, and ecosystem integration … if applicable." The spec substitutes implementation-level detail (affected-files table, parameter signature, pseudocode, test cases). For a single-parameter gate this is defensible, but the standard's core principle is that an unfamiliar reader can confirm the design — and the data flow (findings → report write → count/compare → throw) is only implicit in the pseudocode, never stated as a flow.
- **Recommendation:** Add one short data-flow sentence: evaluation → report written → count findings (all, or at/above `-FailOnSeverity`) → compare to `-FailOnCount` → throw if ≥ threshold. Also note ecosystem integration is unchanged (no new collectors, formats, or rules), which the spec does state at line 18 but not under an architecture heading.

### 4. Nit — Pseudocode variable `$limit` holds a severity rank, not a threshold
- **Scope:** spec line 116.
- **Discrepancy:** `$limit = Get-QuorumSeverityRank $FailOnSeverity` assigns a *severity rank*, yet the variable is named `$limit` and the risk section (line 66) mandates consistent "Threshold" terminology for the count. The message correctly uses "Threshold: {C}" for the count — so this is naming only, not a logic error.
- **Recommendation:** Rename to `$severityLimit`/`$rank` to avoid a reader mistaking it for the count threshold.

### 5. Nit — Inconsistent throw-message shorthand in the User Behavior example
- **Scope:** spec line 28 vs. lines 43–46 and 118.
- **Discrepancy:** Line 28's comment paraphrases the throw as `"...Threshold: 10. Report: ..."` while the authoritative "Error message format" section (lines 45–46) and the pseudocode (line 118) use `"...Threshold: {C}. The report was written to {PATH}."`. A reader comparing the example comment to the canonical format sees a mismatch.
- **Recommendation:** Align the line-28 comment with the canonical wording.

---

**Summary:** 1 Blocker (block placement/precedence makes AC #73 and tests 164/188 unachievable as written), 2 Major (missing interaction risk; missing Proposed Architecture per the standard), 2 Nit. Everything else I checked — line numbers, demo counts (36 findings / 15 high), parameter validation, severity-ranking semantics, help-text content, and the alternatives table (no maintainer-attributed rejections) — is accurate and satisfies the Alternatives Rule and Risks & Limits requirements of the target standard.

### Reviewer: egm-structural (Modell: `kilo/kilo-auto/free`, frischer Prozess)



I'll start by reading the persona file, the target file, the standard, and the context file.
I've read the persona file (`bundle/agents/structural.md`), the target document, the feature-spec standard, and the README context. Here are my findings for the target range **lines 1–84** of `docs/designs/2026-11-03-failoncount-mindestanzahl-an-findings-al.md`.

## Structure map (target scope, lines 1–84)

| Line | Heading |
|------|---------|
| 1 | H1 `# Feature Specification: ...` |
| 3 | H2 Problem Statement |
| 7 | H2 Goals |
| 16 | H2 Non-Goals |
| 23 | H2 User Behavior |
| 48 | H2 Alternatives Considered |
| 58 | H2 Risks & Mitigations |
| 68 | H2 Acceptance Criteria |

Heading hierarchy is clean: H1 → H2s, no skipped levels, no out-of-order sections. Code blocks (lines 25–41) are properly opened and closed. No links present in range, so link compliance is N/A.

## Findings

**1. Severity: Major**
- **Affected Scope:** Target scope lines 1–84; gap between `## Non-Goals` (line 16) and `## User Behavior` (line 23), and nowhere else in range.
- **Discrepancy:** The Feature Specification Standard lists **Proposed Architecture** (component layout, data flows, ecosystem integration) as a mandatory area. The target spec contains no such section in the audited range. The only nearby content is `## Detailed Implementation Plan` / `Logic Changes` starting at line 85, which is outside the audited range and is implementation detail rather than a high-level architecture/data-flow description.
- **Rationale:** A fresh reader cannot see how the new `-FailOnCount` parameter fits into the existing `Invoke-Quorum` flow (materialized findings array → count/filter → compare → throw-after-report) at the architecture level, which the standard requires. The standard's "if applicable to the changes" clause *could* excuse this for a parameter-only change, but the spec states no such rationale, so it fails the mandatory-header check as written. Resolution: add a short architecture/data-flow paragraph in scope, or explicitly document why it is not applicable.

**2. Severity: Nit**
- **Affected Scope:** Line 52, `## Alternatives Considered` table separator row.
- **Discrepancy:** The first column separator uses 13 dashes (`|-------------|`) while the header `Alternative` is 10 chars (12 with padding).
- **Rationale:** Cosmetic only — GitHub Flavored Markdown renders the table correctly. The `Risks & Mitigations` separator (line 61) is already correct (`|------|------------|`). Align the dashes to 12 for consistency.

## Compliance notes (no finding)
- **Alternatives Rule (standard):** Passes. All four rejection rationales state concrete technical/scope trade-offs (parameter-surface explosion, denominator ambiguity, report-first consistency, per-device vs. post-evaluation policy). No rejection is attributed to a maintainer without a linked issue/PR.
- **Risks & Mitigations (standard):** Passes in substance — validation edge cases, `info`-severity interaction, positional-binding breakage, O(n) performance, and terminology consistency are all addressed.

Verdict: **Not fully compliant** — one Major (missing required `Proposed Architecture` section in scope) plus one Nit.

### Reviewer: egm-style (Modell: `kilo/kilo-auto/free`, frischer Prozess)



reviewed the persona file (`egm-style`, read-only, no fluff) and the target range. Here are the findings.

---

**Review target:** `docs/designs/2026-11-03-failoncount-mindestanzahl-an-findings-al.md`, lines 1–84 (Mode: REVIEW)

---

### 1. Major — Lines 28 & 32 vs. Lines 45–46 — Error message format inconsistency
- **Affected scope:** `User Behavior` (lines 26–41) vs. `Error message format` (lines 43–46)
- **Rationale:** The worked examples show the throw message ending in `Report: ...` (lines 28, 32), but the format specification two sections later mandates `The report was written to {PATH}.` (lines 45–46). Both are presented as the actual thrown text. An implementer reading only the examples would ship a different message than the spec defines, and a reviewer checking against the spec would flag the examples as wrong. These must be reconciled to one form. Line 12 ("throw with a message that includes the count, the threshold, and the report path") is neutral on wording, so the tiebreaker is the explicit format table — update lines 28 and 32 to `The report was written to ...`, or vice versa.

### 2. Major — Line 5 — Boundary semantics: "exceed" vs. `≥`
- **Affected scope:** `Problem Statement`, line 5
- **Rationale:** The example `"fail if total findings exceed 50"` uses strict `>` semantics, but the defined behavior (lines 10–11: "throw if count ≥ threshold") and the acceptance criteria (lines 70–71: threshold 36 with 36 findings throws; 37 does not) establish `≥`. At the boundary (exactly 50 findings, threshold 50) the two readings disagree. The companion phrase on the same line ("10 or more") is correct; only "exceed 50" is off. Rewrite as "reach or exceed 50" / "50 or more" to match the `≥` gate.

### 3. Major — Line 63 — Uncalibrated test-coverage claim
- **Affected scope:** `Risks & Mitigations`, row "Interaction with `-FailOnSeverity` when severity is `info`"
- **Rationale:** The mitigation asserts "Test covers this," a claim about existing/tested behavior. No corresponding case appears in the `Acceptance Criteria` list (lines 70–81): the numbered behavioral cases are `critical` (line 74), `high` (lines 72–73), and unfiltered (lines 70–71, 75–76) — no `info` case. Per the audit standard, claims about tested behavior must match their evidence. **Recommended action: CALIBRATE** — either add an `info` acceptance case (e.g., `-FailOnSeverity info -FailOnCount N`) or delete the "Test covers this" assertion until it exists.

### 4. Nit — Line 81 — Case count mismatch ("8 cases")
- **Affected scope:** `Acceptance Criteria`, line 81
- **Rationale:** The line says new Pester tests "cover the 8 cases above," but only 7 behavioral cases are numbered (criteria 1–7, lines 70–76); criterion 8 is help-text documentation, not a test case. The count is reconcilable only if it silently includes the unlisted `info` case from line 63 — but that case is not "above" in the numbered list. Clarify the count or enumerate the cases explicitly.

### 5. Nit — Line 34 — Ambiguous "threshold above actual count"
- **Affected scope:** `User Behavior`, line 34
- **Rationale:** "Pass: threshold above actual count" reads as though the threshold itself is what's above; the intended meaning is that the threshold exceeds the actual finding count. Rephrase to "Pass: threshold is above the actual count" (or "actual count is below threshold") to remove the syntactic ambiguity.

### 6. Nit — Line 54 — Subjective value judgment in a rejection rationale
- **Affected scope:** `Alternatives Considered`, "Fail during evaluation (before report)" row
- **Rationale:** "Consistency is more important than early exit" is an opinionated trade-off assertion, not a measurable fact. Restate it concretely, e.g.: "Current `-FailOnSeverity` writes the report before throwing, so operators always have the artifact; an early exit would require a separate report-write path." That replaces the subjective framing with the actual operational reason.

### 7. Nit — Line 62 — Subjective adjective "clear"
- **Affected scope:** `Risks & Mitigations`, "Parameter validation edge cases" row
- **Rationale:** "throw a clear error for invalid values" uses the subjective qualifier "clear." Specify the contract instead: e.g., "throw a parameter-binding error naming `-FailOnCount` and requiring a value ≥ 1."

---

**Summary:** 2 Major, 1 Major (calibration), 4 Nit. The two Major style/format defects (message format divergence, boundary wording) and the uncalibrated test claim are the items worth fixing before this spec goes to implementation — the first two would otherwise produce an implementation that fails its own spec on the boundary and on the thrown message text.

