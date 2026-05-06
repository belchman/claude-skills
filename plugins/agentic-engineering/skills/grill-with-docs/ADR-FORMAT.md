# ADR Format

ADRs live in `docs/adr/` with sequential numbering: `0001-slug.md`, `0002-slug.md`, etc. Create the directory lazily — only when the first ADR is needed.

## Template

```md
# {Short title of the decision}

{1–3 sentences: context, decision, why.}
```

That's it. An ADR can be a single paragraph. The value is recording *that* a decision was made and *why* — not filling sections.

## Optional sections (use sparingly)

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — useful when decisions are revisited.
- **Considered Options** — only when the rejected alternatives are worth remembering.
- **Consequences** — only when non-obvious downstream effects need calling out.

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one.

## When to offer an ADR

All three must hold:

1. **Hard to reverse** — meaningful cost to change later.
2. **Surprising without context** — a future reader looks at the code and asks *"why on earth?"*.
3. **Real trade-off** — there were genuine alternatives and you picked one for specific reasons.

Easy to reverse → skip; you'll just reverse it. Not surprising → nobody wonders. No real alternative → nothing to record beyond "we did the obvious thing."

### What qualifies

- **Architectural shape.** *"Monorepo." "Write model is event-sourced; read model projects to Postgres."*
- **Integration patterns between contexts.** *"Ordering and Billing communicate via domain events, not synchronous HTTP."*
- **Technology choices with lock-in.** Database, message bus, auth provider, deployment target — not every library, just the ones that take a quarter to swap.
- **Boundary and scope decisions.** *"Customer data is owned by Customer; other contexts reference by ID only."* Explicit no-s are as valuable as yes-s.
- **Deliberate deviations from the obvious path.** *"Manual SQL instead of ORM because X."* Anything where a reasonable reader would assume the opposite. Stops the next engineer from "fixing" something deliberate.
- **Constraints invisible in the code.** *"Can't use AWS due to compliance."* *"Response < 200ms because of a partner contract."*
- **Rejected alternatives when the rejection is non-obvious.** Considered GraphQL, picked REST for subtle reasons → record it, or someone suggests GraphQL again in six months.

<!-- Vendored verbatim from mattpocock/skills@494e4b2699ea (MIT). -->
