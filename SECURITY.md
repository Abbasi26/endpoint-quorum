# Security

Quorum is a read-only reporter. It does not change Intune, Entra ID, or Defender for Endpoint, and it does not send report contents anywhere.

## What stays on your machine

- Live collection downloads device records into the PowerShell session and writes the report files you asked for. There is no telemetry and no default upload.
- `-Demo` does not open a network connection.
- `-Redact` writes `Quorum-RedactionMap.json` beside the report. That file reverses the pseudonyms. Do not attach it to a ticket, email, or pull request. The HTML report is what you share.
- Access tokens are held in memory for the run. Quorum does not write them to the report. Error text is trimmed and any `Bearer` token in an error string is redacted before it is shown.
- Do not commit certificates, PFX passwords, or tenant exports.

## Permissions

The collectors request only the read permissions listed in the README. Do not add write, `ReadWrite`, or broader directory scopes to a Quorum app registration.

Delegated sign-in uses the device-code flow twice (Microsoft Graph, then the Defender API). Certificate sign-in uses a client-assertion JWT. Quorum has no client-secret flow.

## Reporting a vulnerability

Open a private GitHub security advisory on this repository, or contact the maintainer listed in `Quorum.psd1` if advisories are not enabled yet. Please include the version, the command you ran, and whether you used `-Demo` or a live tenant. Do not include a redaction map, tokens, or a full live export.