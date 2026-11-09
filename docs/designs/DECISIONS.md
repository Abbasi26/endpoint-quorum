# Design decisions

## 2026-11-03: `-FailOnCount` Minimum Finding Threshold

**Design:** [2026-11-03-failoncount-mindestanzahl-an-findings-al.md](2026-11-03-failoncount-mindestanzahl-an-findings-al.md)

- **Combined-mode precedence:** When both `-FailOnSeverity` and `-FailOnCount` are provided, the count gate owns the throw and the standalone `-FailOnSeverity` throw is suppressed. Implemented by gating the existing severity block with `if ($FailOnSeverity -and -not $FailOnCount)`.
- **Test patterns use Pester wildcard syntax:** Dropped regex-style escapes (`\(s\)`) in favor of wildcard patterns (`*finding(s)*`) because `Should -Throw` matches via `-like`.
- **Proposed Architecture section added:** Added mandatory architecture/data-flow section per Feature Specification Standard (evaluate → report write → count/filter → throw).
- **ValidateRange uses literal max:** Changed `[ValidateRange(1, [int]::MaxValue)]` to `[ValidateRange(1, 2147483647)]` for absolute clarity, though the original is valid PowerShell.
- **ROADMAP check-off matches table schema:** Updated to 3-column format (Idea, Where to start, Test) with check mark in Test column, not a 4th status column.
- **Parameter binding risk reframed:** Replaced speculative "breaking existing scripts" with accurate "future parameter additions could shift implicit position; use named binding."
- **Message wording calibrated:** Clarified that `-FailOnCount` throws after report in same position as `-FailOnSeverity` but with different wording (adds `Threshold:` token).
- **Terminology unified:** "reaches threshold" / "throws" used consistently across Goals, Help, README, CHANGELOG; "minimum finding threshold" removed.
- **Demo counts cited:** All references to "36 findings, 15 high" now cite `README.md` and `data/demo-inventory.json`.
- **Consciously contested (not fixed):**
  - `[ValidateRange(1, [int]::MaxValue)]` unverified concern — the pattern is valid PowerShell; changed to literal for clarity only.
  - "Placed after `-FailOnSeverity` would split URI parameter group" — parameter placement is a maintainer judgment call; named binding makes it harmless.
## 2026-11-03: Spec drift fixed for `-FailOnCount`

**Design:** [2026-11-03-failoncount-mindestanzahl-an-findings-al.md](2026-11-03-failoncount-mindestanzahl-an-findings-al.md)

- The fresh diff reviewer rejected the first diff because tests used 39/18 while the spec said 36/15.
- Measured demo output is 39 findings, 18 high (rule Q013 added findings after the README text was written), so the spec was wrong, not the code.
- Spec numbers amended to the measured values; mechanism and acceptance criteria unchanged. Lesson: derive demo counts from a run, not from README prose.
