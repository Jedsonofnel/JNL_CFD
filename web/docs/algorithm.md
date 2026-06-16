---
title: Algorithm & Compiler
module: jnl.fvm.algorithm
status: in-progress refactor
---

# Algorithm & Compiler

The algorithm module is responsible for taking a physics registry and producing
an executable plan: a structured, mutable object that drives the solver loop and
can be reasoned about and adapted at runtime by the Sage JTMS system.

The pipeline is:

```
Registry + Algorithm -> SCC detection -> Strategy resolution

-> Plan tree -> FlatCfg + Instruction list -> Coroutine
```

---

## Registry ownership

`Algorithm.new(reg)` takes the registry at construction time. The algorithm and
registry are not siblings — the algorithm owns the registry because it must
reason about the field dependency graph immediately. `Case` then receives a
single algorithm rather than a separate reg+alg pair.

---

## SCC detection

The compiler builds a directed dependency graph from the registry's governing
equations, with one node per solved (prognostic) field and edges representing
read dependencies. It then finds **strongly connected components** (SCCs) — the
maximal subsets of fields that mutually depend on each other.

Fields are classified:

- **SCC size > 1, or size 1 with self-edge** — tightly coupled, requires an explicit resolution strategy.
- **Size 1, no self-edge, feeds into a solved field** — passive diagnostic, evaluated before or after the relevant solve.
- **Size 1, no outgoing edges to solved fields** — post-solution diagnostic, lives in the PostPlan.
- **Pure constants** — evaluated once in the PrePlan.

Diagnostic fields (non-solved, defined by expressions) break apparent cycles:
if the path from field B back to field A passes entirely through diagnostics,
the cycle is lagged naturally and the fields are not placed in the same SCC.

The user never specifies which fields form an SCC. They only resolve SCCs the
compiler has already found.

---

## Strategy resolution

After SCC detection the compiler reports which SCCs need a resolution strategy.
An unresolved SCC is a hard error at compile time. The user selects a strategy
by naming any field within the SCC:

```lua
alg:resolve("U", Strategy.simple())
alg:resolve("k", Strategy.transport())
```

A strategy is a callback that receives the SCC and a builder, and declares the
inner solve structure for that coupling group. Built-in strategies include
`Strategy.simple()`, `Strategy.piso()`, `Strategy.pimple()`, and
`Strategy.transport()`. Custom strategies use the same callback API:

```lua
alg:resolve("U", Strategy.new(function(scc, b)
    b:solve("U")
    b:inner(function(ib)
        ib:zero("p_prime")
        ib:solve("p_prime")
        ib:correct("U")
        ib:correct("p")
    end, opts.n_correctors)
end))
```

Strategies may use field tags (`"velocity"`, `"pressure"`,
`"pressure_correction"`) to locate fields within the SCC portably. Tags are
declared on registry fields and are the only hint surface the compiler uses.

---

## Preflight checks

Before emitting instructions the compiler runs a preflight pass that produces:

- **Errors** — unresolved SCCs, strategy/SCC shape mismatches. Block compilation.
- **Warnings** — assumed field roles from position rather than tag, inferred
  strategies. Compile and run, printed to stderr.
- **Hints** — available via `alg:preflight()` during development only.

Every warning carries the exact registry or algorithm change that would suppress
it, so the edit loop is: run, read warning, apply fix, repeat until clean.

---

## The Plan tree

Compilation produces a **Plan** — a semantic tree that remains alive at runtime
as the target for Sage mutations. Its top-level structure is:

- **PrePlan** — runs once before the outer loop. Evaluates pure constants and
  geometry-derived fields that never change.
- **LoopPlan** — the outer iteration. Contains an ordered sequence of
  `CouplingGroup` nodes (topo-sorted by inter-SCC dependencies) followed by
  a `MonitorBlock`.
- **PostPlan** — runs once after convergence. Passive scalar transport,
  final diagnostics.

Each `CouplingGroup` corresponds to one resolved SCC and carries:

- The field set.
- The strategy's inner solve structure (`SolvePlan`, `InnerBlock`,
  `CorrectPlan`, `ZeroPlan`).
- A config store (relaxation, solver, tolerances) that inherits from a
  group-level default.
- A per-field pseudo-dt table (nil means steady).
- An `inner_n` value that Sage can mutate to tighten coupling.

---

## Requirements

Each plan node declares its **requirements** — what must be computed or kept
fresh before it can execute. Requirements are topo-sorted and deduplicated
within each step using a `FreshnessState` that tracks a generation counter and
which requirements have been satisfied in the current outer iteration.

Built-in requirement types:

- `GhostReq(field)` — ghost cell fill for boundary conditions.
- `GradReq(field)` — cell-centred gradient.
- `FaceFluxReq(kind, ...)` — face-interpolated flux, including Rhie-Chow
  for `mwi` expressions.
- `DivReq(field)` — divergence of a face flux.
- `EvalReq(field)` — evaluation of a diagnostic expression.
- `CloseBCReq(field, patch)` — matrix boundary condition closure.

Freshness is scoped to the current iteration's completed groups: a requirement
satisfied inside one `CouplingGroup` is considered fresh for subsequent groups
in the same outer iteration, but stale at the start of the next.

---

## Configuration and emission

At emit time the Plan compiles its group config hierarchy into a flat
`FlatCfg` — a field-keyed table that Dispatch reads at runtime. Group
inheritance (group-level defaults overridden by field-level values) is resolved
once at emit time, not at dispatch time. Instructions carry only a field name
and op; they have no knowledge of which group they belong to.

Two kinds of mutation are distinguished:

- **Config changes** (`plan:set_cfg`) — update a value in the group config and
  re-flatten into a new `FlatCfg`. No instruction re-emission. Dispatch reads
  the new value next iteration.
- **Scheme changes** (`plan:set_scheme`) — change the instruction shape (e.g.
  `uds` to `tvd`). Triggers `plan:emit_from(group)`, re-emitting the affected
  group's instruction subtree and rebuilding the coroutine from that point.

Sage pushes config changes as `set_config` actions and scheme changes as
`set_scheme` actions. The distinction is explicit in the action kind.

---

## Monitors

`reg:monitor(name, expr)` declares a named observable quantity. Monitors are
not persistent cell fields — they compute an expression, aggregate it (L2 norm
by default), and emit a named telemetry fact to Sage. The `MonitorBlock` at the
end of each loop iteration evaluates all monitors, checking freshness to avoid
recomputing intermediate quantities already calculated inside a coupling group.

Convergence criteria reference monitor names directly:

```lua
alg:converge(Rules.norm_below("continuity", 1e-6))
```

---

## Sage integration

`CouplingGroup` is the unit of Sage reasoning. Supported actions:

- `set_config` — mutate a config value, re-flatten FlatCfg.
- `set_scheme` — change discretisation scheme, partial re-emit.
- `set_pseudo_dt` — enable or disable pseudo-transient stabilisation per field.
- `tighten_coupling` — increment `inner_n` on a group.
- `merge_into` — move one coupling group inside another's inner loop.
- `stop` — halt the solver with a reason string.

All mutations are applied at iteration boundaries via the existing
`handle_iteration_end` → `pop_actions` → `handle_action` sequence in `Case`.

---

## File structure

```
fvm/
  algorithm/
    init.lua          -- Algorithm.new(reg), resolve(), converge(), guard()
    scc.lua           -- dependency graph construction, Kosaraju/Tarjan
    strategy.lua      -- Strategy base, built-in strategies
    preflight.lua     -- error/warning/hint system

  plan/
    init.lua        -- Plan root, Pre+Loop+Post assembly
    pre.lua         -- PrePlan
    loop.lua        -- LoopPlan
    post.lua        -- PostPlan
    coupling.lua    -- CouplingGroup, Sage mutation API
    inner.lua       -- InnerBlock
    monitor.lua     -- MonitorPlan
    solve.lua       -- SolvePlan
    eval.lua        -- EvalPlan
    correct.lua     -- CorrectPlan
    zero.lua        -- ZeroPlan
    freshness.lua   -- FreshnessState, generation tracking
    emitter.lua     -- Plan tree -> flat Inst list + FlatCfg
    listing.lua     -- human-readable plan dump

  requirements/
    init.lua        -- Req base, topo-sort, dedup
    ghost.lua       -- GhostReq
    grad.lua        -- GradReq
    face_flux.lua   -- FaceFluxReq (Rhie-Chow for mwi)
    div.lua         -- DivReq
    eval.lua        -- EvalReq
    close_bc.lua    -- CloseBCReq

instruction.lua     -- flat bytecode structs, unchanged
dispatch.lua        -- Case execution, reads FlatCfg by field name
case.lua            -- executor, holds plan + cfg + instructions + coro
rules.lua           -- Sage convergence/divergence criterion constructors
preset.lua          -- thin named presets returning configured Algorithm
```
