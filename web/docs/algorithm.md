---
title: Algorithm & Compiler
module: jnl.fvm.physics
status: in-progress refactor
---

# Algorithm & Compiler

The physics module is responsible for taking a combined physics and solve
sequence specification and producing an executable plan: a structured, mutable
object that drives the solver loop and can be reasoned about and adapted at
runtime by the Sage JTMS system.

The pipeline is:

```
Physics (registry + solve sequence)
    -> compile()
    -> Plan tree (Pre + Loop + Post)
    -> FlatCfg + Instruction list
    -> Coroutine
```

---

## The Physics object

`Physics` is the single object a user constructs to describe a simulation.
It owns both the field registry and the solve sequence. There is no separate
registry and algorithm to assemble — one object is passed to `Case`.

```lua
local case = Case.new(physics, mesh, bcs)
```

Physics exposes the registry declaration API directly so field declarations and
sequence declarations live in one place:

```lua
local p  = Physics.new("stokes")
local nu = p:const("nu", 1e-3)
local U  = p:vector("U")
local pr = p:scalar("p")
local pp = p:scalar("p_prime")

U:governed_by(nb.laplacian(nu * U):equals(nb.grad(-pr)))

local inv_d = p:scalar("inv_d"):defined_as(
    nb.cV() * 2 / (U:diag().x + U:diag().y))

pp:governed_by(
    nb.laplacian(inv_d * pp):equals(-nb.div(nb.mwi(U, pr))))

U:correction(-nb.cV() * nb.grad(pp) / U:diag())
pr:correction(pp)

p:monitor("continuity", nb.div(U))

p:loop(function(b)
    b:solve("U"):tag("momentum")
    b:inner(function(ib)
        ib:zero("p_prime")
        ib:solve("p_prime")
        ib:correct("U")
        ib:correct("p")
    end, 1):tag("pressure_correction")
end)

p:converge(Rules.norm_below("continuity", 1e-6))
p:guard(Rules.nan_guard())
p:set_cfg("U", "relax", 0.7)
```

---

## Field vocabulary

Four kinds of field exist in the registry. The kind determines where in the
Plan the field is handled.

- **SolvedField** — declared with `governed_by`. Has a governing equation
  and a linear system. Appears explicitly in the solve sequence.
- **AlgebraicField** — declared with `defined_as`. Computed from an
  expression over other fields. Evaluated on demand as a requirement of
  whichever solve step reads it.
- **Monitor** — declared with `physics:monitor(name, expr)`. Evaluated at
  each iteration end as a scalar aggregate (L2 norm by default). Emits a
  named telemetry fact to Sage. Not a persistent cell field.
- **Constant** — declared with `physics:const(name, value)`. Folded at
  compile time into instruction coefficients. Use `physics:dynamic(name,
  value)` for constants Sage may update at runtime without recompilation.

The distinction between SolvedField and AlgebraicField is the user's explicit
decision about lagging. Declaring `mu_t` as an AlgebraicField means its value
is lagged across outer iterations. Writing its expression inline in another
field's equation creates a tighter dependency; the user controls this through
representation, not through annotations.

---

## Solve sequence

The user declares the solve sequence explicitly using a builder callback.
The only structural decision is where inner loops appear — everything else
is topological order within the outer loop.

```lua
p:loop(function(b)
    b:solve("U"):tag("momentum")
    b:inner(function(ib)
        ib:zero("p_prime")
        ib:solve("p_prime")
        ib:correct("U")
        ib:correct("p")
    end, 1):tag("pressure_correction")
    b:solve("k"):tag("scalar_transport")
    b:solve("epsilon")
    b:evaluate("mu_t")
end, max_iters)
```

Builder methods:

- `b:solve(field)` — assemble and solve the linear system for a SolvedField.
- `b:evaluate(field)` — explicitly evaluate an AlgebraicField.
- `b:correct(field)` — apply the field's declared correction expression.
- `b:zero(field)` — fill a field with zero before assembly.
- `b:inner(cb, n)` — insert a sub-loop running at most `n` times per outer
  iteration. Returns the inner builder for further steps. `n` is the Sage-
  mutable handle for coupling tightness.
- `b:fill(field, value)` — fill a field with a constant.

Each step may be tagged with `:tag(name)` to create a named insertion
point for physics modifiers.

---

## The Plan tree

Compilation produces a **Plan** — a semantic tree that remains alive at runtime
as the target for Sage mutations.

```
Plan
  PrePlan
  LoopPlan
    SolvePlan("U")
    InnerLoop("pressure_correction", n=1)
      ZeroPlan("p_prime")
      SolvePlan("p_prime")
      CorrectPlan("U")
      CorrectPlan("p")
    SolvePlan("k")
    SolvePlan("epsilon")
    EvalPlan("mu_t")
    MonitorBlock
      MonitorPlan("continuity")
  PostPlan
```

**PrePlan** runs once before the outer loop. It evaluates constants and
AlgebraicFields that depend only on constants and geometry — quantities that
never change across iterations.

**LoopPlan** is the outer iteration. It contains a flat ordered list of plan
nodes produced directly from the user's sequence declaration. Each node is
one of: `SolvePlan`, `InnerLoop`, `EvalPlan`, `CorrectPlan`, `ZeroPlan`.
A `MonitorBlock` runs at the end of each outer iteration.

**PostPlan** runs once after convergence. It is for one-shot final
computations: derived output quantities, error norms, and pure passive
scalar transport where a single solve against the converged velocity field
is sufficient. A reactive scalar or any field that feeds back into the loop
belongs in LoopPlan, not PostPlan.

### InnerLoop

`InnerLoop` is the primary Sage-mutable structural node. It replaces the
earlier `CouplingGroup` concept. It carries:

- A named tag string (`"pressure_correction"`, `"turbulence"`, etc.)
  that Sage uses to address it.
- `n` — the current inner iteration count. Sage may increment this.
- `max_n` — the ceiling declared by the user.
- A flat list of child plan nodes.

Sage can also move a plan node into an existing InnerLoop, or extract one out
of it, by rebuilding the affected subtree. These are structural mutations
distinct from config or scheme changes.

---

## Requirements

Each plan node declares its **requirements** — what must be computed or kept
fresh before execution. Requirements are topo-sorted and deduplicated within
each step using a `FreshnessState` that tracks a generation counter.

Freshness requirements (must hold before a step executes):

- `GhostReq(field)` — ghost cell fill for boundary conditions.
- `GradReq(field)` — cell-centred gradient.
- `FaceFluxReq(kind, ...)` — face-interpolated flux, including Rhie-Chow
  for `mwi` expressions.
- `DivReq(field)` — divergence of a face flux.
- `EvalReq(field)` — evaluation of an AlgebraicField expression.

Assembly requirements (produced during linear system construction):

- `MatrixResetReq(field)` — zero and resize the linear system.
- `CoeffReq(node)` — evaluate a coefficient expression into scratch storage.
- `SourceReq(field)` — assemble source and linearisation terms.
- `BoundaryClosureReq(field, patch)` — apply matrix boundary conditions.

Freshness is scoped to the current iteration's completed steps. A requirement
satisfied inside an InnerLoop is fresh for subsequent steps in the same outer
iteration, but stale at the start of the next outer iteration.

---

## Configuration and emission

At emit time the Plan compiles its per-field config into a flat `FlatCfg` — a
field-keyed table that Dispatch reads at runtime. Config inheritance (Physics-
level defaults overridden by field-level values) is resolved once at emit time.
Instructions carry only a field name and op; they have no knowledge of plan
structure.

Three mutation categories are explicitly distinguished:

- **Config changes** (`plan:set_cfg`) — update a relaxation factor, tolerance,
  or solver selection. Re-flattens FlatCfg only. No instruction change.
  Dispatch reads the new value on the next iteration.
- **Scheme changes** (`plan:set_scheme`) — change discretisation (e.g. `uds`
  to `tvd`). Triggers partial re-emission of the affected plan node's
  instruction subtree. Coroutine is rebuilt from that point.
- **Structural changes** — add or remove a step, change InnerLoop `n`,
  move a node into or out of an InnerLoop. Rebuilds the affected Plan subtree
  and re-emits all instructions from that subtree downward.

Dynamic constants (`physics:dynamic`) are read from a registry value slot at
eval time rather than being folded at compile time. Updating them is a config
change with no recompilation. Use for turbulence model coefficients or any
value Sage may tune.

---

## Monitors

`physics:monitor(name, expr)` declares a named observable quantity. Monitors
are not persistent cell fields. At each iteration end the `MonitorBlock`
evaluates each monitor expression, aggregates it (L2 norm by default), and
emits a named telemetry fact to Sage.

Freshness is checked before evaluation: if a requirement of the monitor
expression (e.g. a face flux) was already satisfied by a preceding SolvePlan
in the same iteration, the monitor reuses it rather than recomputing.

Convergence criteria reference monitor names:

```lua
p:converge(Rules.norm_below("continuity", 1e-6))
p:converge(Rules.norm_below("k",          1e-5))
```

---

## SCC detection as a validation tool

SCC detection runs after the solve sequence is declared, as an optional
validation pass. It is not structural — the Plan is built from the user's
explicit sequence, not from detected SCCs.

The validator warns when the declared solve order appears inconsistent with
mathematical dependencies:

```
WARN  "U" is solved before "k", but "U"'s equation reads "k" as a coefficient.
      If this lag is intentional, suppress with p:lag("k", "U").
      If not, move b:solve("k") before b:solve("U") in the sequence.
```

The user may acknowledge an intentional lag explicitly:

```lua
p:lag("k", "U")   -- "I know U reads k; treating this as lagged is deliberate"
```

This suppresses the warning without changing the solve order. The declaration
also serves as documentation of the modelling choice.

---

## Physics modifiers

Modifiers add to both the registry and the solve sequence atomically. They
insert fields and equations into the registry and new steps into the sequence
at named tags.

```lua
p:with_buoyancy({ beta = 3e-3, T_ref = 300, g = { 0, -9.81 } })
-- Adds:   T (SolvedField), buoyancy source term to U's equation
-- Inserts: b:solve("T") after the "momentum" tag

p:with_spalart_allmaras({ Cb1 = 0.1355 })
-- Adds:   nu_t (AlgebraicField), chi (AlgebraicField), nu_tilde (SolvedField)
--         modifies effective viscosity in U's equation
-- Inserts: b:solve("nu_tilde") after "momentum" tag

p:with_k_epsilon({ C_mu = 0.09 })
-- Adds:   k, epsilon (SolvedFields), mu_t (AlgebraicField)
-- Inserts: b:inner(function(ib) ib:solve("k"); ib:solve("epsilon") end, 1)
--          after "momentum" tag, or after "scalar_transport" if present
```

Modifiers read and write named tags but do not assume absolute positions.
If a required tag is absent the modifier errors with a clear message. The
base sequence declares which tags exist; modifiers declare which tags
they require.

For higher-level selection, presets compose base physics with standard
modifiers:

```lua
local p = preset.rans_ke({ nu = 1e-5 })
-- equivalent to:
--   Physics.new():with_ns():with_k_epsilon():simple()
```

---

## Sage integration

`InnerLoop` is the primary unit of Sage reasoning. Supported actions at
iteration boundaries:

- `set_config` — mutate a config value (relax, tol, solver). Re-flattens
  FlatCfg.
- `set_scheme` — change a discretisation scheme. Partial re-emit of affected
  subtree.
- `set_inner_n` — change an InnerLoop's iteration count. Structural mutation,
  rebuilds that subtree.
- `set_pseudo_dt` — enable or disable pseudo-transient stabilisation per
  field. Config change if dt value only; structural change if the ddt term
  is added or removed from the equation.
- `stop` — halt the solver with a reason string.

All mutations are applied at outer iteration boundaries via the existing
`handle_iteration_end` -> `pop_actions` -> `handle_action` sequence in Case.

---

## File structure

```
fvm/
  physics/
    init.lua        -- Physics.new(); registry delegation; loop(), inner()
    modifiers.lua   -- with_buoyancy(), with_spalart_allmaras(), with_k_epsilon()

  algorithm/
    scc.lua         -- SCC detection (validation tool, not structural)
    preflight.lua   -- dependency order warnings, lag() declarations

  plan/
    init.lua        -- Plan root; Pre + Loop + Post assembly
    pre.lua         -- PrePlan
    loop.lua        -- LoopPlan; ordered node list
    post.lua        -- PostPlan; one-shot final computations
    inner.lua       -- InnerLoop; Sage-mutable sub-loop node
    solve.lua       -- SolvePlan
    eval.lua        -- EvalPlan
    correct.lua     -- CorrectPlan
    zero.lua        -- ZeroPlan
    monitor.lua     -- MonitorBlock and MonitorPlan
    freshness.lua   -- FreshnessState; generation tracking
    emitter.lua     -- Plan tree -> flat Inst list + FlatCfg
    listing.lua     -- human-readable plan dump

  requirements/
    init.lua        -- Req base; topo-sort; dedup
    ghost.lua       -- GhostReq
    grad.lua        -- GradReq
    face_flux.lua   -- FaceFluxReq; Rhie-Chow for mwi
    div.lua         -- DivReq
    eval.lua        -- EvalReq
    close_bc.lua    -- BoundaryClosureReq
    matrix.lua      -- MatrixResetReq, CoeffReq, SourceReq

  instruction.lua   -- flat bytecode structs; unchanged
  dispatch.lua      -- Case execution; reads FlatCfg by field name
  case.lua          -- executor; holds Plan + FlatCfg + instructions + coro
  rules.lua         -- convergence/divergence criterion constructors
  preset.lua        -- named presets returning configured Physics objects
```
