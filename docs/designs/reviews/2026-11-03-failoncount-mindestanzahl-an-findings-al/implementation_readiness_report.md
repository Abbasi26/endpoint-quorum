# Stage 9: Implementation Readiness (DetailedRange 96..251)
### Reviewer: egm-implementation-readiness (Modell: `kilo/kilo-auto/free`, frischer Prozess)



I'll start by reading the persona file, the target design document, and the standard.
Now let me read the persona file, the agent standard, and the actual source files referenced in the plan.
✗ Grep "Get-QuorumSeverityRank" failed in .
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.

### Reviewer: egm-codebase-details (Modell: `kilo/kilo-auto/free`, frischer Prozess)



I'll start by reading the persona file, the target design document, and the standard file.
Now let me explore the repository structure to verify all the claims in the plan.
✗ exec {"command":"cd /home/wasafabbasi11/repos/endpoint-quorum && grep -n '\"groups\"\\|\"administrativeUnits\"\\|\"asOf\"\\|\"tenantLabel\"' data/demo-inventory.json | head -20"} failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ exec {"command":"cd /home/wasafabbasi11/repos/endpoint-quorum && which pwsh && pwsh -NoProfile -Command \"Import-Module ./Quorum.psd1; \\$r = Invoke-Quorum -Demo -OutputPath /tmp/qc-check 6>`$null; 'FindingCount=' + \\$r.FindingCount; 'HighestSeverity=' + \\$r.HighestSeverity; \\$high = @(\\$r.Findings | Where-Object { [string]\\$_['severity'] -eq 'high' }); 'HighCount=' + \\$high.Count; \\$sevCounts = @{}; foreach (\\$f in \\$r.Findings) { if (-not \\$sevCounts.ContainsKey([string]\\$f['severity'])) { \\$sevCounts[[string]\\$f['severity']] = 0 }; \\$sevCounts[[string]\\$f['severity']]++ }; \\$sevCounts | Format-Table -AutoSize\" 2>&1 | tail -40"} failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
I've read all the required files. Let me verify a few more details before compiling findings.

### Reviewer: egm-style (Modell: `kilo/kilo-auto/free`, frischer Prozess)



✗ Grep "FailOnSeverity|Get-QuorumSeverityRank|Findings|finding" failed in Public/Invoke-Quorum.ps1
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ grep -c '"severity"' data/demo-inventory.json; echo "---rules---"; ls rules/ 2>/dev/null | head; echo "---findings in inventory---"; grep -o '"findings"' data/demo-inventory.json | head failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ grep -rn "function Get-QuorumSeverityRank" . 2>/dev/null; echo "---"; grep -rn "Get-QuorumSeverityRank" --include=*.ps1 . | head -20 failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ ls rules/ 2>/dev/null; echo "---"; ls data/ 2>/dev/null failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ which pwsh && pwsh -NoProfile -Command "Import-Module ./Quorum.psd1; `$r = Invoke-Quorum -Demo -OutputPath /tmp/quorum-verify 6>`null; `$r.FindingCount; (`$r.Findings | Group-Object Severity | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ', '; (`$r.Findings | Where-Object Severity -eq high).Count" failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ which pwsh && pwsh -NoProfile -Command "Import-Module ./Quorum.psd1; $r = Invoke-Quorum -Demo -OutputPath /tmp/quorum-verify 6>$null; $r.FindingCount; ($r.Findings | Group-Object Severity | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ', '; ($r.Findings | Where-Object Severity -eq high).Count" failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ command -v pwsh || echo "no pwsh"; command -v pwsh.exe || echo "no pwsh.exe"; ls /usr/bin | grep -i powershell || true failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ echo hello failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
I read the persona file (`egm-style`: strict read-only technical copy editor, claim-calibration mandate) and the target range. I then checked the design's claims against the actual source: `Public/Invoke-Quorum.ps1` (esp. the existing `-FailOnSeverity` block at lines 305–312), `Private/Quorum.Internal.ps1` (`Get-QuorumSeverityRank`, lines 264–274), `Private/New-QuorumViewModel.ps1` (finding shape), `tests/V02Features.Tests.ps1` (existing `-Throw` conventions), `README.md`, `CHANGELOG.md`, `ROADMAP.md`, and the 12 shipped rules.

## Findings

### 1. Blocker — Test patterns use regex escaping that Pester's wildcard matcher will reject
- **Lines:** 164, 175, 199 (consequence surfaces at line 244, "all tests pass")
- **Discrepancy:** The proposed `-Throw` patterns are written with regex-style escapes: `*total finding\(s\)*Threshold: 36*`, `*severity high or worse*Threshold: 10*`, `*severity info or worse*Threshold: 36*`. Pester 5's `Should -Throw <string>` matches as a **wildcard** (`-like`), where `\` is a literal character and `(` `)` are literal — so these patterns require the literal text `finding\(s\)` and will never match the thrown message `...total finding(s). Threshold: 36...`.
- **Rationale:** Proof is in this repo's own existing tests — `V02Features.Tests.ps1:90` uses `*severity high or worse*`, which is invalid regex (`*` with nothing to repeat) and therefore only valid as a wildcard. The design's escaping convention contradicts the file it is appended to. Under wildcard semantics all three tests fail, which blocks CI per `AGENTS.md`.
- **Action:** CALIBRATE — rewrite as `*total finding(s)*Threshold: 36*`, `*severity high or worse*Threshold: 10*`, `*severity info or worse*Threshold: 36*` (drop the backslashes), then confirm under Pester 5.9.1.

### 2. Major — Line 143 overstates consistency with `-FailOnSeverity`
- **Line:** 143 ("Throws **after** report is written (consistent with `-FailOnSeverity`)"), anchored by the proposed messages at lines 129 and 133
- **Discrepancy:** The claim is true for *ordering/timing* but false for *message wording*. The existing throw at `Invoke-Quorum.ps1:309` is:
  `Quorum found {0} finding(s) at severity {1} or worse. The report was written to {2}.`
  The design's combined message (line 129) inserts `. Threshold: {2}.` and the total-only message (line 133) restructures to `Quorum found {0} total finding(s). Threshold: {1}. ...`. The two gate messages will not be word-for-word consistent, and the tests at 175/199 are anchored on the new `Threshold:` token that the existing message does not have.
- **Rationale:** This is an uncalibrated claim about existing behavior, and it creates an implementation trap: an implementer honoring "consistent with `-FailOnSeverity`" (copy line 309's wording) silently breaks the new tests.
- **Action:** CALIBRATE — either (a) drop `Threshold: {n}` from the new messages to match the existing format and update the test patterns, or (b) keep the new format and reword line 143 to "throws after the report is written, in the same position as `-FailOnSeverity`; the message wording differs and adds the threshold."

### 3. Nit — Line 207 overgeneralizes "Each test verifies the report file exists"
- **Line:** 207, covering the block at lines 161–202
- **Discrepancy:** Only the three throw-on-threshold tests (lines 165, 176, 200) assert `Test-Path ... Quorum-Report.html`. The two validation tests (lines 190, 194) throw during parameter validation — before any report is written — and assert only `Should -Throw`.
- **Rationale:** "Each test" is a false claim about the suite; it also hides the fact that zero/negative thresholds are gated before report writing.
- **Action:** CALIBRATE — reword to "The throw-on-threshold tests verify the report file exists; the validation tests throw before a report is written."

### 4. Nit — Line 218 "minimum finding threshold" drifts from the documented semantics
- **Line:** 218 (README proposal), with help text at line 150 and changelog at line 233
- **Discrepancy:** `-FailOnCount 36` *fails* when the count *reaches* 36, so 36 is a fail-when-reached ceiling, not a floor. The help text (line 150: "throw if the number of findings reaches this threshold") and the changelog (line 233: "fails the run when the finding count reaches a threshold") use "reaches", while line 218 says "adds a minimum finding threshold".
- **Rationale:** Same feature, three framings; "minimum" invites the opposite mental model (raise the floor).
- **Action:** CALIBRATE — align README with the help text: "`-FailOnCount` fails the run when the finding count reaches this threshold."

### 5. Nit — Line 233 changelog mixes metaphors with the existing style
- **Line:** 233, against `CHANGELOG.md:12`
- **Discrepancy:** The existing entry says "`-FailOnSeverity` throws after the report is written". The proposed entry says "fails the run when the finding count reaches a threshold … Report is written before throwing." "Fails the run" and "throws" are two different verbs for the same mechanism in adjacent entries.
- **Rationale:** Minor redundancy/terminology drift in a file readers treat as the change record.
- **Action:** CALIBRATE — use "throws" consistently, e.g. "`-FailOnCount` parameter for `Invoke-Quorum`: throws after the report is written when the finding count reaches a threshold."

## Verified consistent (KEEP, not findings)
- **Line 116:** `ValidateRange(1, [int]::MaxValue)` rejects 0 and negatives — accurate; the standard PowerShell `ParameterValidationException` is a fair characterization.
- **Lines 120, 141–144:** placement (after `$result`, after the existing block at 305–311), reuse of `Get-QuorumSeverityRank` (rank ≤ limit = same/worse), `$model['findings']` already evaluated, no mutation of `$result` — all match `Invoke-Quorum.ps1` and `New-QuorumViewModel.ps1` exactly.
- **Lines 128/130/132/135:** the severity-filter and `-ge` comparison are a faithful copy of the existing logic at lines 307/308; the count semantics (36 throws, 37 passes, high=15 throws at 10 and passes at 20, info counts all 36) are internally self-consistent.
- **Line 205 ("36 findings, 15 high"):** agrees with `README.md:12` ("15 high and 21 medium") and with the existing high-severity gate test at `V02Features.Tests.ps1:90`. I could not execute `pwsh` in this environment to independently re-derive the counts; treat as KEEP and let CI's `Invoke-Pester ./tests` confirm.
- **Lines 206, 246–250:** `6>$null` suppressing the Write-Host information stream and the manual demo runs are factual and correctly transcribed.

**Bottom line:** the draft is unusually dry and well-calibrated for a code design, but it ships with one CI-blocking test bug (Finding 1) and one overbrought consistency claim (Finding 2) that must be resolved before the Pester gate at line 244 can be trusted.

