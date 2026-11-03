# Stage 5: Initial Zoom Out Review
### Reviewer: egm-zoom-out (Modell: `kilo/kilo-auto/free`, frischer Prozess)



I'll start by reading the required files in parallel.
Now let me verify the design's claims against the actual codebase.
✗ exec {"command":"cd /home/wasafabbasi11/repos/endpoint-quorum && python3 -c \"\nimport json\nd=json.load(open('data/demo-inventory.json'))\nprint('keys',list(d.keys()))\nprint('asOf',d.get('asOf'))\n\""} failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
✗ exec {"command":"cd /home/wasafabbasi11/repos/endpoint-quorum && grep -rn \"Get-QuorumSeverityRank\" --include=*.ps1 | head -50"} failed
Error: Model tried to call unavailable tool 'invalid'. Available tools: glob, read.
I read the persona file, the Zoom-Out Standard, the Goldfish Context (README), and the target design, then verified the design's claims against the actual codebase (`Public/Invoke-Quorum.ps1`, `Private/New-QuorumViewModel.ps1`, `tests/V02Features.Tests.ps1`, `CHANGELOG.md`, `ROADMAP.md`, `data/demo-inventory.json`).

## Gate checks (standard)

- **Context sufficiency (§0): pass.** Objective, motivation, and demo counts are stated; the reviewer can tell *what* and *why*.
- **Root problem focus (§1): pass.** A count gate is the actual need; no symptom-patching.
- **Reuse (§4): pass.** No new utilities are proposed. Verified `Get-QuorumSeverityRank` exists (`Private/New-QuorumViewModel.ps1:264`, already used at `Invoke-Quorum.ps1:307`), `$model['findings']` exists (`New-QuorumViewModel.ps1:92`), and `$written.HtmlPath` exists. Good — no wheel reinvention.
- **YAGNI / anti-weeds (§2–3): pass.** No speculative features; pseudocode is proportionate for a ~15-line change.

## Findings

### 1. Blocker — Combined `-FailOnSeverity` + `-FailOnCount` behavior is self-contradictory
- **Lines:** Goals `10`, User Behavior `27–28`, Logic Changes `109–128` (pseudocode `113–128`), Test Cases `162–171` and `186–190`, Acceptance Criteria `3, 4, 8`.
- **Discrepancy:** The design defines the combined mode (count findings at severity or worse, throw with the `Threshold: <C>` message) but places the new gate **after** the existing `-FailOnSeverity` block, which it says is at `Invoke-Quorum.ps1:305–311`. That existing block throws on **any** finding at the severity (`-gt 0`), unconditionally, whenever `$FailOnSeverity` is set. So with both parameters present, the *existing* block throws first — its message is `"...at severity high or worse. The report was written to ..."` and contains **no** `Threshold:` token.
- **Rationale / broken artifacts:**
  - Test at `164` expects `'*severity high or worse*Threshold: 10*'` → fails (message has no `Threshold: 10`).
  - Test at `168–171` expects **no throw** when 15 high < 20 → fails (existing block throws on any high finding).
  - Test at `188–189` (`-FailOnSeverity info -FailOnCount 36`) expects `'*severity info or worse*Threshold: 36*'` → fails for the same reason.
  - The User Behavior example at `27–28` promises the `Threshold: 10` message, confirming intent — so the *plan* is wrong, not the intent.
- **Fix:** the design must specify modifying/suppressing the existing block when `-FailOnCount` is present (e.g., run the count gate first and skip the severity-only throw, or merge into one gate). As written, AC 3/4/8 cannot pass.

### 2. Major — Stray closing fence in the proposed README snippet
- **Lines:** Documentation Changes / README snippet `202–217`.
- **Discrepancy:** The ```powershell block opens at `208` and closes at `215`; line `217` is a **second, unmatched** ```. If this snippet is applied verbatim into `README.md`, that stray fence opens an unterminated code block that swallows the following `## Live, read-only collection` section (and beyond) until the next fence, corrupting rendering.
- **Rationale:** Directly contradicts Acceptance Criterion `9` ("README renders correctly on GitHub"). Remove the duplicate fence at `217`.

### 3. Nit — "param block" wording for help text
- **Lines:** `104`, `135–143`.
- **Discrepancy:** The design says place `.PARAMETER FailOnCount` "after `-FailOnSeverity` in the param block." The `.PARAMETER` entries actually live in the `<# ... #>` comment block (compare `Invoke-Quorum.ps1:78–80` for `FailOnSeverity`), not the `param(...)` block.
- **Rationale:** Cosmetic, but an implementer following it literally would put help text in the wrong place.

### 4. Nit — Speculative "breaking change" risk
- **Line:** `64` (Risks & Mitigations).
- **Discrepancy:** "Breaking existing scripts that pass `-FailOnCount` as positional." The parameter does not exist yet, so nothing can already pass it; and a `[int]$FailOnCount` is named-only by default.
- **Rationale:** Not a real risk for a new parameter. Drop the row or reframe it as a naming-convention note.

### 5. Nit — `[ValidateRange(1, [int]::MaxValue)]` unverified
- **Lines:** `100–105`.
- **Discrepancy:** Attribute arguments must be constant expressions; `[int]::MaxValue` is a static-member expression that may not parse as an attribute constant in PowerShell (behavior varies; I could not execute `pwsh` in this environment to confirm).
- **Rationale:** If it fails to parse, the module won't load. Safer to use a literal `[ValidateRange(1, 2147483647)]` or a runtime `if` check. Flag for verification before merge.

### 6. Nit — Demo counts asserted without a cited source
- **Lines:** `27`, `152`, `194`.
- **Discrepancy:** "36 findings, 15 high" is stated as fact. It matches `README.md:12`, but the design never cites that source, and the numbers could drift silently.
- **Rationale:** Low impact now; recommend referencing `README.md` / `data/demo-inventory.json`.

---

**Summary:** 1 Blocker (the combined-mode logic placement, which breaks 3 of the 8 proposed tests and 3 acceptance criteria), 1 Major (stray fence that would corrupt README rendering), 4 Nits. The core concept is sound and reuse is good; the Blocker must be resolved before this design is implementable.

