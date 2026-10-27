# Changelog

## 0.1.0 - 2026-10-21

First public slice.

- Read-only collectors for Intune managed devices, Entra ID devices, and Defender for Endpoint machines.
- Device matching on the Entra device id, with hostname and short-hostname fallback and a confidence value.
- Twelve starter rules in `rules/`.
- `Invoke-Quorum` writes a self-contained HTML report, a Markdown summary, and CSV and JSON findings.
- `-Demo` runs offline on a bundled synthetic inventory.
- `-Redact` pseudonymizes hostnames, user names, UPNs, and IP addresses for one run and writes a local reversal map.
- Pester tests and a GitHub Actions workflow for PowerShell 7 and Windows PowerShell 5.1.