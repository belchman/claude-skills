# Refactor playbook

Load this only when step 9 of `SKILL.md` picks the **refactor** path. Match the language of the worst offender; read only its section plus the generic patterns at the end.

Each pattern lists:
- **Trigger** — the shape you're looking at.
- A minimal **before/after**.

None of these mention the specific function — they're idioms you layer onto the user's code.

---

## Python

### Guard-clause / early return
**Trigger**: nested `if` pyramid where the happy path is deepest.
```python
# before
def handle(req):
    if req.is_authenticated():
        if req.payload is not None:
            if req.payload.valid():
                return process(req.payload)
            else:
                return error("invalid")
        else:
            return error("missing")
    else:
        return error("unauth")

# after
def handle(req):
    if not req.is_authenticated():
        return error("unauth")
    if req.payload is None:
        return error("missing")
    if not req.payload.valid():
        return error("invalid")
    return process(req.payload)
```

### `match` / dispatch dict for stringly-typed branches
**Trigger**: `if x == "a": ... elif x == "b": ...` ladders.
```python
# before
if kind == "csv": return parse_csv(x)
elif kind == "json": return parse_json(x)
elif kind == "xml": return parse_xml(x)
else: raise ValueError(kind)

# after
PARSERS = {"csv": parse_csv, "json": parse_json, "xml": parse_xml}
def parse(kind, x):
    try:
        return PARSERS[kind](x)
    except KeyError:
        raise ValueError(kind)
```

### Replace flag-arg with separate functions
**Trigger**: `def do(..., dry_run: bool, verbose: bool, strict: bool)` where branches only depend on the flags.
```python
# after: callers pick the function; each variant is half as complex.
def do_strict(...): ...
def do_relaxed(...): ...
```

### Extract helper for a named block
**Trigger**: a 20-line block inside a 60-line function that a comment labels (`# validate inputs`, `# render footer`).
Extract it, name the helper with the comment's text, delete the comment.

### Data-class / `TypedDict` instead of parallel lists
**Trigger**: functions that thread `(ids, names, amounts)` tuples through every branch.
Introduce a dataclass; CC drops because the branches stop re-selecting indices.

---

## JavaScript / TypeScript

### Early return over nested conditionals
Identical shape to the Python guard-clause pattern.

### `Array.prototype.{filter,map,reduce}` over imperative loops
**Trigger**: `for` loop that mutates an accumulator conditionally.
```ts
// before
const out = [];
for (const u of users) {
  if (u.active && !u.banned) out.push({id: u.id, n: u.name});
}
// after
const out = users
  .filter(u => u.active && !u.banned)
  .map(u => ({id: u.id, n: u.name}));
```

### Lookup table / dispatch object for switch ladders
**Trigger**: `switch` over a string discriminant with small bodies.
Replace with `const HANDLERS: Record<Kind, (x: T) => U> = {...}`.

### Extract async step into its own function
**Trigger**: a function with 4+ `await`s and branching in between. Each `await` branch adds CC.
Extract the pre-await validation and the post-await transformation into separate named helpers.

### Discriminated union instead of boolean flags
**Trigger**: `{ok: true, value?} | {ok: false, error?}`-style objects threaded through branches.
Use a tagged union `{ status: 'ok'; value: T } | { status: 'err'; error: E }` + exhaustive `switch`; TS narrows automatically.

---

## Go

### Early return on errors (idiomatic Go)
**Trigger**: `if err == nil { ... } else { return err }` inverted pyramids.
```go
// after
if err != nil { return err }
// happy path continues at top level
```

### Table-driven dispatch
**Trigger**: chained `switch`/`if` on a string kind.
```go
var handlers = map[string]func(Input) (Output, error){
    "csv":  parseCSV,
    "json": parseJSON,
}
fn, ok := handlers[kind]
if !ok { return Output{}, fmt.Errorf("unknown kind %q", kind) }
return fn(input)
```

### Small interface at the call site
**Trigger**: a function that takes a `*BigStruct` but uses 2 methods.
Define a tiny interface `type reader interface{ Read() ([]byte, error) }`, accept that instead; tests get trivial and CC of callers drops.

### Split on error vs. happy-path state machines
**Trigger**: nested state checks interleaved with I/O.
Extract each transition into a helper returning `(newState, error)`.

---

## Rust

### Pattern match over `if let Some` ladders
**Trigger**: `if let Some(x) = opt { if let Some(y) = x.thing() { ... } }`.
```rust
// after
match opt.and_then(|x| x.thing()) {
    Some(y) => { ... }
    None => { ... }
}
```

### `?` operator for error plumbing
**Trigger**: manual `match` on `Result` that propagates `Err` unchanged.
```rust
// before
let x = match get()? { Ok(v) => v, Err(e) => return Err(e) };
// after
let x = get()?;
```

### Enum-dispatch instead of nested conditionals
**Trigger**: logic branching on "what kind of thing is this" where the kinds are known.
Define an enum with a method per kind; each variant handles its own branch.

### Split trait impls to shrink per-method CC
**Trigger**: one `impl` block with a 150-line method covering four kinds.
Give each kind its own `impl` and a shared trait.

---

## Java / Kotlin

### Strategy pattern instead of `switch` over types
Classic GoF. Each case becomes a class; the dispatcher just looks up the strategy.

### Optional chaining / `?.` for null ladders (Kotlin)
**Trigger**: nested null checks.
```kotlin
// before
if (a != null) { if (a.b != null) { if (a.b.c != null) return a.b.c.d } }
// after
return a?.b?.c?.d
```

### Stream API over manual loops
Same logic as the JS `filter/map/reduce` pattern.

---

## C / C++

### Early `goto cleanup` for resource unwind
**Trigger**: nested `if (foo)` around resource acquisition + cleanup.
Classic Linux-kernel style — one cleanup label, jump on any failure, resources released in reverse order.

### Table-driven handlers
**Trigger**: `switch` on an enum with many cases.
Replace with `handler_fn handlers[N] = { [KIND_A] = handle_a, ... };` indexed by the enum.

### `const`-correctness to split read-paths from write-paths
A read-only variant of a mixed read/write function often has 1/3 the CC.

---

## Generic patterns (any language)

- **Sink parametric behavior into data.** If a function's branching is driven by a fixed set of values, turn those values into a table and look them up.
- **Invert conditionals to flatten nesting.** Handle the failure/short-circuit case first and `return` early.
- **Extract named sub-steps.** Any comment labeling a block is a refactor signal — make the comment a function name.
- **Delete impossible branches.** Dead `else` arms under exhaustive checks inflate CC without adding behavior.
- **Stop catching everything.** Broad `except Exception` / `catch(...)` wrapping the whole function usually hides branching that could be at the top.
