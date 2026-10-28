# Roadmap

Quorum stays read-only. Every item here reads data or writes local files; none of them changes a tenant.

## 0.2 (in progress)

- [x] Offline import of existing exports (`-InventoryPath`, `-IntunePath`, `-EntraPath`, `-DefenderPath`)
- [x] `-FailOnSeverity` for scheduled runs and pipelines
- [x] `Test-QuorumRule` rule linter, run in CI
- [ ] MECM as a fourth read-only source through the AdminService
- [ ] Rule ids and severities in the Markdown summary header, for ticket systems

## Later

- **0.3**: an interactive graph of the matched devices, built from the local report.
- **0.4**: a CVE briefing from the OS builds already collected. No new permission.

## Good first issues

Small, self-contained, and each one comes with an obvious test.

| Idea | Where to start | Test |
| --- | --- | --- |
| `Test-QuorumRule` warns when a rule has no `remediation` longer than one sentence | `Public/Test-QuorumRule.ps1` | new case in `tests/V02Features.Tests.ps1` |
| `-FailOnSeverity` also accepts a minimum finding count (`-FailOnCount`) | `Public/Invoke-Quorum.ps1` | demo run with a threshold above and below 36 |
| Starter rule: Entra device disabled but still compliant in Intune | `rules/` | `Invoke-Quorum -Demo -RulesPath` plus `Test-QuorumRule` |
| Accept a gzip-compressed export (`.json.gz`) in the offline import | `Read-QuorumExportFile` | round-trip of `data/demo-inventory.json` |
| Add a `-Format` switch that writes only the JSON findings (for automation) | `Private/New-QuorumReport.ps1` | file list in the output folder |
| Document how to export the three inventories with Graph Explorer | `README.md` | review only |

Pick one, comment on the issue (or open one with the "Feature request" form), and keep the change small. See [CONTRIBUTING.md](CONTRIBUTING.md).
