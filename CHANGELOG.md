# Changelog

## Unreleased

- CI: PowerShell 7.6 LTS (7.6.9, SHA-256 pinned) via `.github/actions/install-pwsh-7-6`; PowerShell 7.4 and 7.5 reach end of support on 10 Nov 2026 ([support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle)). Windows PowerShell 5.1 unchanged.

## 0.2.0 - 2026-10-28

- Offline import: `-InventoryPath` for one combined file, or `-IntunePath`, `-EntraPath`, and `-DefenderPath` for separate exports. Each file can be a JSON array or a raw API page with `value`. Missing sources are reported as not provided. `-AsOf` sets the reference time.
- `-FailOnSeverity` throws after the report is written when a finding reaches the given severity. The result now includes `HighestSeverity`.
- New command `Test-QuorumRule` lints rule files: required fields, duplicate ids, unknown facts and operators, missing values, and undefined `valueFrom` parameters. CI lints the shipped rules.
- ROADMAP.md with good first issues, issue forms, and a pull request template.

## 0.1.0 - 2026-10-21

First public slice.

- Read-only collectors for Intune managed devices, Entra ID devices, and Defender for Endpoint machines.
- Device matching on the Entra device id, with hostname and short-hostname fallback and a confidence value.
- Twelve starter rules in `rules/`.
- `Invoke-Quorum` writes a self-contained HTML report, a Markdown summary, and CSV and JSON findings.
- `-Demo` runs offline on a bundled synthetic inventory.
- `-Redact` pseudonymizes hostnames, user names, UPNs, and IP addresses for one run and writes a local reversal map.
- Pester tests and a GitHub Actions workflow for PowerShell 7 and Windows PowerShell 5.1.