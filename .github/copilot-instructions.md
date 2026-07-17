# Copilot Instructions

## Git Commits

- When asked to commit changes, split them into multiple logical commits rather than one big commit.
- Group related files together (e.g. module changes, entry-point changes, SQL changes, docs separately).
- Commit messages must be plain natural language - no conventional commit prefixes like `feat:`, `fix:`, `chore:`, etc.
- Keep messages short - a single concise sentence is ideal.
- Example good messages: `Add duplicate key check logic`, `Fix connection string sanitization`, `Update readme with new parameters`.

## PowerShell Version Target

All scripts in this project target **PowerShell 5.1** (64-bit) running on Windows Server.
PowerShell 5.1 uses the system ANSI code page to read script files and does NOT handle
non-ASCII Unicode characters transparently the way PowerShell 7 does.

## Critical: ASCII-Only Characters in .ps1 Files

**Never use non-ASCII characters in any `.ps1` file.** This includes:

| Character | Unicode | Name | Use instead |
|-----------|---------|------|-------------|
| `—`       | U+2014  | Em dash | `-` or ` - ` |
| `–`       | U+2013  | En dash | `-` or ` - ` |
| `…`       | U+2026  | Ellipsis | `...` |
| `"` `"`   | U+201C/D | Smart quotes | `"` |
| `'` `'`   | U+2018/9 | Smart quotes | `'` |

**Why it breaks PS 5.1:** The UTF-8 bytes for an em dash (`E2 80 94`) are re-interpreted
as three separate Windows-1252 characters (`â€"`), which the PowerShell 5.1 parser then
treats as command tokens or operators, causing `CommandNotFoundException` or silent
corruption of string output.

