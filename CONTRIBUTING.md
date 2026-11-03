# Contributing

Quorum is a small PowerShell module. Changes should stay read-only, work in PowerShell 7 on Windows, macOS, and Linux, and keep Windows PowerShell 5.1 working where the module already does.

## Setup

```powershell
Import-Module ./Quorum.psd1
Invoke-Quorum -Demo
Invoke-Pester ./tests
```

Pester 5.9.1 is what CI installs. Windows PowerShell 5.1 ships an older Pester; install 5.9.1 for the current user before you run the tests:

```powershell
Install-Module Pester -RequiredVersion 5.9.1 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module Pester -RequiredVersion 5.9.1
```

## Add a rule

1. Copy an existing file in `rules/` to a new name such as `Q013-short-name.yaml`.
2. Give it a new id, a severity (`critical`, `high`, `medium`, `low`, or `info`), and the fields in the README rule section.
3. Use facts the engine already publishes. If you need a new fact, add it in `Private/Get-QuorumFact.ps1` and cover it with a test.
4. Run `Invoke-Quorum -Demo` and confirm the rule fires only on the devices you expect.
5. Add a Pester example that builds two or three records and asserts the rule id.

Do not put real hostnames, UPNs, tenant ids, or customer names in rules, tests, or the demo inventory.

## Add a collector

Put a new `Get-Quorum*` function in its own file under `Collectors/`. The module loads every `.ps1` in that folder. The collector must be a GET (or equivalent read) and must return objects from a `ConvertTo-Quorum*Record` function. Document the permission in the file comment and in the README table. Do not request a write scope.

Wire the collector into `Invoke-Quorum` only after the normalizer and a matching test exist.

## Style

- ASCII in `.ps1`, `.psm1`, and `.psd1` files. If a file must contain non-ASCII text, save it as UTF-8 with BOM so Windows PowerShell 5.1 reads it correctly.
- No new modules or libraries. The YAML parser, report, and redaction are in-tree on purpose.
- Do not claim a source, rule, or switch that the code does not implement.

## Before you open a pull request

- `Invoke-Quorum -Demo` finishes and writes HTML, Markdown, CSV, and JSON.
- `Invoke-Pester ./tests` passes in PowerShell 7.6 LTS.
- If you touched matching, rules, or redaction, the new behavior has a test that does not call the network.