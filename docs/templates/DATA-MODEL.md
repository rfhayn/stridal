> TEMPLATE, not filled in. Do not treat as project fact.

# Data model

Copy to `docs/DATA-MODEL.md`, fill in, and delete the marker line above.

## Entities
```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    USER {
        id uuid PK
        email text
    }
    ORDER {
        id uuid PK
        user_id uuid FK
    }
    LINE_ITEM {
        id uuid PK
        order_id uuid FK
    }
```

## Notes
{{Constraints, indexes, retention, who owns each table, anything the diagram can't say.}}
