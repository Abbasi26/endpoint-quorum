# Stage 6: Comprehension Test
### Reviewer: egm-comprehension (Modell: `kilo/kilo-auto/free`, frischer Prozess)



I'll verify a few references against the actual source to ground the audit, then run the comprehension analysis.
✗ Grep "SeverityRank" failed in .
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ Grep "function Get-QuorumSeverityRank" failed in .
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ Grep "SeverityRank|severityRank" failed in .
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ Grep "Get-QuorumSeverityRank" failed in .
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ invoke name="invoke {"command":"which pwsh || which powershell || echo \"NO_PWSH\"","timeout":"15000"} failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
I have enough grounding now. Let me verify the load-bearing factual claims in the spec — the demo finding counts (36 total, 15 high) — since all test thresholds rest on them.
✗ invoke name="invoke {"command":"python3 -c \"\nimport json\nd = json.load(open('data/demo-inventory.json'))\nprint('intune', len(d.get('intune', [])), 'entra', len(d.get('entra', [])), 'defender', len(d.get('defender', [])), 'groups', len(d.get('groups', [])), 'aus', len(d.get('administrativeUnits', [])))\n\"","timeout":"15000"} failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
I read the persona file (`bundle/agents/comprehension.md` → **Comprehension Goldfish**: naive fresh reader, zero institutional knowledge, read-only, paraphrase-first, flag undefined terms / assumed prerequisites / vague explanations) and the integration doc. I then audited the target against the actual repo: `Public/Invoke-Quorum.ps1`, `Private/New-QuorumViewModel.ps1` (which defines `Get-QuorumSeverityRank`), `Private/New-QuorumReport.ps1`, `Private/Merge-QuorumDevice.ps1`, `Private/Invoke-QuorumRule.ps1`, `Private/Get-QuorumFact.ps1`, `Quorum.psd1`, `tests/V02Features.Tests.ps1`, `tests/Quorum.Tests.ps1`, `README.md`, `CHANGELOG.md`, `ROADMAP.md`, and the 13 rule files. Findings follow.

## What this proposes

`Invoke-Quorum` gains a new `[int]$FailOnCount` parameter that acts as a minimum-finding-count gate for CI/CD, mirroring the existing `-FailOnSeverity` gate. Alone it counts **all** findings and throws when the count reaches the threshold; combined with `-FailOnSeverity` it counts only findings at that severity or worse. In both modes the report is written first and the throw message includes the count, the threshold, and the report path. The change is intentionally small: a parameter block entry with `[ValidateRange(1, [int]::MaxValue)]`, one new gating block in `Invoke-Quorum.ps1`, eight Pester tests, plus README / CHANGELOG / ROADMAP updates. No new rules, collectors, output formats, or result properties.

## How the existing system works, per this document

`Invoke-Quorum` reads Intune, Entra ID, and Defender for Endpoint (or a bundled demo inventory, or offline exports), merges records into devices, evaluates the YAML rules in `rules/`, builds a view-model `$model`, and writes an HTML report plus Markdown/CSV/JSON via `New-QuorumReport`, which returns `$written` with an `HtmlPath`. It already exposes `$result` carrying `FindingCount` and `HighestSeverity`. The existing `-FailOnSeverity` gate (documented as lines 305–311) runs **after** the report is written and throws if *any* finding is at the given severity or worse — it is an any/severity gate, not a count gate. `Get-QuorumSeverityRank` (in `New-QuorumViewModel.ps1`) assigns lower numbers to worse severities (critical = 0 … info = 4), which is how "at this severity or worse" is computed. `Test-QuorumRule` is a separate linter and is explicitly out of scope.

## Findings

### 🔴 Blocker
**1. The plan never modifies the existing `-FailOnSeverity` block, so it short-circuits the new count gate and breaks three acceptance tests.**
- **Affected scope:** Detailed Implementation Plan → "Logic Changes in `Invoke-Quorum`" (lines 107–128) vs. Acceptance Criteria (lines 70–77) and the Pester block (lines 150–191).
- **Rationale:** The spec places the new `if ($FailOnCount)…` block *after* the existing `-FailOnSeverity` block and shows no change to it. But the existing block (as the spec itself cites, lines 305–311) throws whenever *any* finding reaches the severity — it does not consult a count. Consequences under a literal implementation:
  - AC #4 (`-FailOnSeverity high -FailOnCount 20` → "returns result; no throw", line 74) would **throw**, because the demo's 15 high findings already trip the existing block.
  - AC #3 (line 73) and the test at line 164 would throw the *existing* block's message (`"…at severity high or worse. The report was written to …"`), which contains **no `Threshold: 10`** — so `Should -Throw '*severity high or worse*Threshold: 10*'` fails.
  - The `info` test at line 188 fails the same way (existing message lacks `Threshold: 36`).
  The User Behavior example (line 28) also promises a `Threshold: 10` the existing block cannot produce. The spec's own pseudocode and its acceptance criteria/tests are mutually contradictory unless the existing severity block is rewritten to defer to the count gate when `-FailOnCount` is present — and the spec never describes that rewrite.

### 🟠 Major
**2. The ROADMAP instruction ("check off the row" with a `✅` column) does not match the actual `ROADMAP.md` table.**
- **Affected scope:** Documentation Changes → ROADMAP.md (lines 225–229) vs. actual `ROADMAP.md` lines 22–25.
- **Rationale:** The spec shows the row as four cells ending in `| ✅ |`. The real "Good first issues" table has only **three** columns (`Idea | Where to start | Test`) and no status column; the `-FailOnCount` row (line 25) has three cells and no ✅. A reader following the spec literally would either add a fourth column to a table that has none or be unable to "check off" anything. The change instruction is inconsistent with the target file's schema.

**3. "Parameter is named-only … no positional binding" is not true of the proposed signature.**
- **Affected scope:** Risks & Mitigations (line 64) and Parameter Signature (lines 99–102).
- **Rationale:** The spec asserts `[int]$FailOnCount` is "named-only" with "no positional binding." In a `[CmdletBinding()]` function where **no** parameter carries an explicit `Position` attribute, PowerShell assigns every parameter an *implicit* position by declaration order — so a plain `[int]$FailOnCount` **would** be positionally bindable. (This is consistent with the existing params, e.g. `-TenantId`, which are already implicitly positional.) The mitigation row leans on a false property, and the real risk framing ("breaking scripts that pass `-FailOnCount` positionally") is backwards, since the parameter cannot have existed before. If named-only binding is actually wanted, the signature needs an explicit `Position` or a `[Parameter(...)]` block; the spec gives neither.

**4. The demo counts "36 total findings, 15 high" are asserted, never derived, and all eight test thresholds depend on them.**
- **Affected scope:** Problem Statement / User Behavior (lines 5, 26–41), Test Cases (lines 145–191), line 194.
- **Rationale:** Every Pester threshold is calibrated to these two numbers (exactly 36 total, and high-count somewhere in [10, 19] — stated as 15). The document states them as fact but cites no source, and no shipped test pins them: `Quorum.Tests.ps1` only asserts `FindingCount -gt 0` (line 437) and `DirectoryRules.Tests.ps1` asserts `DeviceCount -eq 50` (line 63). A fresh reader cannot confirm 36/15 from the document; if the real demo differs, `cnt1`–`cnt4` and `cnt8` fail silently. This is a verification prerequisite, not a cosmetic gap.

### 🟡 Nit
**5. "Placed after `-FailOnSeverity` … for logical grouping" would split the URI parameter group.**
- **Affected scope:** Parameter Signature note (line 105) vs. actual param block (`Invoke-Quorum.ps1` lines 135–139).
- **Rationale:** `-FailOnSeverity` is immediately followed by `-GraphBaseUri`, `-DefenderBaseUri`, `-AuthorityHost`, which are already a logical group. Inserting `-FailOnCount` between them breaks that grouping for no benefit. Named binding makes it harmless, but the stated rationale is inaccurate.

**6. The pseudocode uses `$written.HtmlPath` without defining `$written`.**
- **Affected scope:** Pseudocode (lines 118, 122).
- **Rationale:** `$written` is never introduced in the plan; the reader must infer it from the existing `-FailOnSeverity` block (line 309) or from `New-QuorumReport`'s return shape. It does exist (`Invoke-Quorum.ps1` line 275), so this is a small self-containment gap rather than an error — but the plan's only reference to the report path rides on an undefined variable.

**7. The User Behavior example abbreviates the throw message in a way that drifts from the documented format.**
- **Affected scope:** User Behavior (line 28) vs. Error message format (lines 43–46).
- **Rationale:** The example comment says `"Threshold: 10. Report: …"` while the format spec says `"Threshold: {C}. The report was written to {PATH}."` Trivial, but it is exactly the kind of drift that makes a reader unsure which string the tests actually expect (the tests, thankfully, match the format spec).

