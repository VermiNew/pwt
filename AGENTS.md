# Agent Instructions

## Project overview

PowerShell 7+ personal toolbox (`pwt`) loaded via `$PROFILE`.
Each tool lives in `Scripts/pwt-<name>.ps1` and self-registers with the `pwt`
dispatcher defined in `Scripts/_pwt-core.ps1`.

## Workflow: Iterative

Never write large amounts of code in a single step. Follow this cycle:

1. **Plan** — define one small, concrete goal.
2. **Write** — implement only that piece.
3. **Verify** — run the pipeline below.
4. **Fix or commit** — broken → fix → re-verify; working → commit.
5. **Repeat.**

### Verification pipeline

```powershell
pwt parse          # AST syntax check (no execution)
pwt bom            # UTF-8 BOM check; fix with: pwt bom -Fix
. $PROFILE         # reload profile and smoke-test the new command
```

### Key principles

- **A commit is a reward for working code**, not written code.
- **Every commit must be a working state.**
- **Small steps prevent compounding errors.**

## Commit convention

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

```
<type>(scope): <description>
```

Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `style`, `test`
Scope = tool name, e.g. `feat(phone): add Wi-Fi reconnect option`

## Safety & communication

- **Never `git add .`** — always `git status` + `git diff`, stage only relevant files.
- **Ask before deleting** any file, function, or significant block of code.
- **Discuss before acting** on non-trivial changes; proceed autonomously only for small safe edits.

## Code hygiene

- **No new external tools/dependencies without approval.**
- **Don't refactor unrelated code** — only touch what the current task requires.
- **Don't write tests unless asked.**
- **Read before writing** — understand existing patterns first.
- **Don't over-engineer** — do exactly what was asked, nothing more.

## File conventions

- Encoding: **UTF-8 with BOM** (`EF BB BF`) for every `.ps1` / `.psm1`.
  Verify: `pwt bom` · Fix: `pwt bom -Fix`
  Manual check: `pwsh -NoProfile -Command "(Format-Hex file.ps1 -Count 3).Bytes -join ' '"`
- Every script starts with:
  ```powershell
  #!/usr/bin/env pwsh
  #requires -Version 7.0
  ```

## Adding a new tool

1. Create `Scripts/pwt-<name>.ps1` — one file per tool.
2. Main function name: `Invoke-Pwt<Name>` with full `.SYNOPSIS` / `.DESCRIPTION` / `.EXAMPLE` help.
3. Use `Write-PwtHost` (not `Write-Host`) for all output. Preferred `-Style` values:
   `Accent`, `Ok`, `Warn`, `Error`, `Muted`, `Heading`, `Text`.
4. Guard external binaries:
   ```powershell
   if (-not (Test-PwtTool -Name 'foo' -Description '...' -Winget 'Vendor.Foo')) { return }
   ```
5. Destructive ops: `[CmdletBinding(SupportsShouldProcess)]` + `$PSCmdlet.ShouldProcess(...)`.
6. Admin ops: `Test-PwtAdmin` + `Invoke-PwtElevated`.
7. Register at the bottom:
   ```powershell
   if (Get-Command Register-PwtCommand -ErrorAction SilentlyContinue) {
       Register-PwtCommand -Name '<name>' -Category '<category>' `
           -Synopsis '...' `
           -Function 'Invoke-Pwt<Name>' `
           -Requires @('<tool>')
   }
   ```

Valid categories (display order): `system`, `network`, `files`, `clipboard`, `download`, `dev`, `phone`, `printer`, `misc`

## Project language

- UI / interactive messages: **Polish**
- Code (variables, functions, comments): **English**
