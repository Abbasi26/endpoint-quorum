# Original task specification (from cloud agent transcript)

Build v0.1 of **Quorum**, a new open-source tool meant to be published on GitHub later under the MIT license. Write all code, comments and README in English. Add a short German summary section at the end of the README.

## Idea
Endpoint admins see a different truth in each console. Intune can say a device is compliant while Microsoft Defender for Endpoint hasn't seen it in 40 days. Entra ID keeps stale device objects that Conditional Access still trusts. OS versions and last check-ins disagree between sources. Quorum fetches the per-device state from each source **read-only**, matches devices across sources, and reports the **contradictions themselves as security signals**. Out of scope for v0.1 (existing tools such as Microsoft365DSC, Maester, CIPP and the native CA What-If cover these): config drift, policy-as-code, Conditional Access simulation and MECM. See the attached uploads (stand_der_technik.md = prior-art research, ideen_runde1.md = design discussion) for context.

## v0.1 scope
- PowerShell 7 module `Quorum` (also works in Windows PowerShell 5.1 where feasible). It must be cross-platform, because many admins run pwsh on macOS or Linux.
- Collectors, all read-only, each in its own file so the community can add more:
  - Intune managed devices via Microsoft Graph (DeviceManagementManagedDevices.Read.All)
  - Entra ID devices via Graph (Device.Read.All)
  - Defender for Endpoint machines via the Defender API (Machine.Read.All) or Graph security, whichever needs the fewest permissions
  - Auth: delegated interactive or app-only with certificate. Document the exact minimal permissions in a table. Never request write scopes.
- Device matching across sources by Entra deviceId / azureADDeviceId, with a fallback to hostname, plus a confidence value.
- Rules engine. Rules live as YAML files in `rules/`, each with an id, title, severity, description, why-it-matters, remediation hint and a condition. Ship about 8–12 sensible starter rules, for example:
  - compliant in Intune but no Defender contact for more than N days
  - Entra device enabled but no Intune record
  - Intune device without a Defender onboarding
  - OS build mismatch between sources
  - stale Entra object (no sign-in for more than N days) still enabled
  - duplicate devices per hostname
  - Defender risk high while Intune says compliant
- One command, `Invoke-Quorum`, that writes three outputs:
  - a self-contained, nice-looking HTML report with severity filter and per-device drilldown; no external CDN, inline CSS/JS only
  - a Markdown summary
  - CSV/JSON
- `-Demo` switch that runs fully offline on a bundled synthetic dataset (about 50 fictional devices with clearly fake names, no real company data) and produces the report in under 60 seconds. This is the key onboarding experience.
- Optional `-Redact` that pseudonymizes hostnames, UPNs and IPs consistently, so reports can be shared.
- Pester 5 tests for matching, rules and redaction, all runnable offline on the demo data, plus a GitHub Actions workflow running them on ubuntu-latest (pwsh) and windows-latest (pwsh and powershell 5.1). Watch the file encodings: UTF-8 with BOM for .ps1/.psm1 files that contain non-ASCII characters, or keep them ASCII-only.
- README: a one-line pitch, the problem with a concrete example, a 60-second quickstart (Demo), real usage, a permissions table, how rules work and how to contribute one, and a roadmap (v0.2 MECM AdminService, v0.3 interactive graph view, v0.4 CVE briefing from the device inventory). Also include a security and privacy section (read-only; data stays local; no telemetry), CONTRIBUTING.md, LICENSE (MIT, copyright "Wasaf Abbasi"), CHANGELOG.md and SECURITY.md.

## Hard rules
- Write everything from scratch. Use no employer or customer code or data, no customer names, no real tenant data, and no mention of any employer, government client or security clearance.
- Put no secrets in the repo.
- Don't claim features that aren't implemented. The README must match the code.

## Done when
The module imports, `Invoke-Quorum -Demo` produces the HTML, MD and CSV reports, all Pester tests pass locally, and the CI workflow file is present. In the final report, list the file tree, the rules you shipped, the permissions table, and anything left unfinished. Add a screenshot of the demo HTML report as an artifact.
