# CONTEXT.md Format

## Structure

```md
# {Context Name}

{One or two sentence description of what this context is and why it exists.}

## Language

**Order**:
A concise description of the term.
_Avoid_: Purchase, transaction

**Invoice**:
A request for payment sent to a customer after delivery.
_Avoid_: Bill, payment request

**Customer**:
A person or organization that places orders.
_Avoid_: Client, buyer, account

## Relationships

- An **Order** produces one or more **Invoices**
- An **Invoice** belongs to exactly one **Customer**

## Example dialogue

> **Dev:** "When a **Customer** places an **Order**, do we create the **Invoice** immediately?"
> **Domain expert:** "No — an **Invoice** is only generated once a **Fulfillment** is confirmed."

## Flagged ambiguities

- "account" was used to mean both **Customer** and **User** — resolved: distinct concepts.
```

## Rules

- **Be opinionated.** When multiple words exist for one concept, pick the best and list the others under "Avoid".
- **Flag conflicts.** Ambiguous use of a term goes under "Flagged ambiguities" with a clear resolution.
- **Tight definitions.** One sentence max. Define what it IS, not what it does.
- **Show relationships.** Bold term names and express cardinality where obvious.
- **Project-specific only.** General programming concepts (timeouts, error types, utility patterns) don't belong, even if used heavily. Before adding a term, ask: unique to this context, or general programming? Only the former.
- **Group under subheadings** when natural clusters emerge. Flat list is fine for cohesive areas.
- **Write an example dialogue** between a dev and a domain expert that exercises the terms naturally and clarifies boundaries.

## Single vs multi-context

- **Single (most repos):** one `CONTEXT.md` at the root.
- **Multiple:** a `CONTEXT-MAP.md` at the root listing the contexts, where they live, and how they relate.

```md
# Context Map

## Contexts

- [Ordering](./src/ordering/CONTEXT.md) — receives and tracks customer orders
- [Billing](./src/billing/CONTEXT.md) — generates invoices, processes payments
- [Fulfillment](./src/fulfillment/CONTEXT.md) — warehouse picking and shipping

## Relationships

- **Ordering → Fulfillment**: Ordering emits `OrderPlaced` events; Fulfillment consumes to start picking
- **Fulfillment → Billing**: Fulfillment emits `ShipmentDispatched`; Billing consumes to invoice
- **Ordering ↔ Billing**: shared types for `CustomerId` and `Money`
```

Inference order:

1. `CONTEXT-MAP.md` exists → multi-context; read it.
2. Only root `CONTEXT.md` → single context.
3. Neither exists → create root `CONTEXT.md` lazily on first term resolution.

For multi-context: infer which context the current topic relates to. Ask if unclear.

<!-- Vendored verbatim from mattpocock/skills@494e4b2699ea (MIT). -->
