> TEMPLATE, not filled in. Do not treat as project fact.

# Inventory

Copy to `docs/INVENTORY.md`, fill in, and delete the marker line above.

**Names and locations only. Never put secret values here.**

**Keep this file out of public repos.** Names, locations and account details are a map for an attacker, and they stay in git history even after the file is deleted.

## Secrets
| Name | Where it lives | Used by | Rotated |
|---|---|---|---|
| {{STRIPE_API_KEY}} | {{password manager entry / GitHub Actions secret}} | {{service or workflow}} | {{date}} |

## Services/Infra
| Service | Purpose | Account / owner | Location |
|---|---|---|---|
| {{name}} | {{one line}} | {{account name, not credentials}} | {{URL or console path}} |
