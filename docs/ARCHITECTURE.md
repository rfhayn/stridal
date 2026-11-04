> TEMPLATE, not filled in. Do not treat as project fact.

# Architecture

Delete the marker line above once this is filled in and true. Keep it to one page; link to ADRs for the why.

## What this is
{{One paragraph: what the system does and for whom.}}

## Components
| Component | Responsibility | Tech | Where it lives |
|---|---|---|---|
| {{name}} | {{one line}} | {{language/framework}} | {{path or service}} |

## How data flows
{{Request/event path through the components, in a few lines or a mermaid block.}}

## External dependencies
{{Services, APIs and accounts this relies on. Names only; see docs/templates/INVENTORY.md.}}

## Constraints and decisions
{{Things a change must not break. Link each decision to docs/adr/NNNN-*.md.}}
