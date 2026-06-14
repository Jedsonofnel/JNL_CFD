
# General role

You are helping write code for JNL, a compact scientific-computing,
geometry, meshing, and CFD environment built around C and Lua.
Prefer code that is easy to inspect, modify, test, and use
interactively.

The API reference appended to this context is generated directly
from the Lua source files. Treat it as the primary description of
the available public API.

If a function, method, option, type, or return value is absent or
unclear in the API reference, do not invent it. State the ambiguity
and ask for the relevant source when necessary.


# Writing JNL library code

- Prefer clear, shallow Lua code.
- Use tabs for indentation.
- Use early returns to keep control flow flat.
- Prefer small local helpers over deeply nested blocks.
- Keep public module functions easy to find.
- Avoid unnecessary abstraction and speculative generality.
- Do not prefix Lua names with underscores to imply privacy. Lua has no private fields or methods, and the convention is visually noisy without enforcing anything.
- Express privacy structurally: keep implementation helpers local, avoid exporting internal values, and use @private only for documentation visibility.
- Comment only to explain non-obvious behaviour, constraints, invariants, or design decisions.
- Use plain ASCII in comments, documentation, identifiers, and user-facing diagnostic text; do not use Unicode arrows, mathematical symbols, or typographic punctuation.
- Do not add decorative rulers or banners beyond the standard three-line section header.
- When changing a public API, update its source annotations in the same change.


# Source documentation

JNL documentation is derived from Lua source comments. Do not create
or maintain parallel _doc, _api, _types, or _constants tables.

- Document public modules, functions, methods, values, classes, aliases, parameters, returns, and fields using LuaLS-style annotations.
- Put each documentation block immediately before the declaration it documents.
- Use ordinary -- comments for implementation notes that should not appear in the API reference.
- Use @private when a declaration would otherwise appear public but should be excluded.
- Keep documentation concise and describe behaviour rather than restating the function name.
- Do not document unsupported behaviour merely because it might be useful.
- Use @private for documentation visibility; do not rename public or internal symbols with leading underscores merely to suggest privacy.


# Documentation comment style

Use this style for prose documentation:

--- Create a triangulation specification.

Use annotation lines without a space between --- and @:

---@param area number Maximum permitted triangle area.
---@return Spec self

The scanner accepts both ---Text and --- Text, but new code should
use a single space after --- for prose. Annotation lines should use
the conventional ---@ form.

- Write prose as complete sentences with terminal punctuation.
- Keep the first sentence short enough to work as a summary.
- Use blank --- lines to separate documentation paragraphs.
- Do not add indentation solely to align annotation descriptions.


# Documenting modules and functions

Document a module near its declaration:

--- Build and query two-dimensional meshes.
local M = {}

Document public functions immediately before their definitions:

--- Return a mesh generated from the supplied domain.
---@param domain Domain Geometry to triangulate.
---@param opts? table Triangulation options.
---@return Mesh mesh
function M.triangulate(domain, opts)

- Annotate every public parameter whose type is not obvious to the scanner.
- Use name? for optional parameters, such as @param opts? table.
- Add one @return line for each return value.
- Include return names when they improve clarity, such as @return Mesh mesh.
- Do not add annotations to trivial private helpers unless their types improve editor diagnostics.


# Documenting types

Use named classes for public object-like tables:

---@class TriSpec
---@field quiet boolean Suppress Triangle output.
---@field min_angle number Minimum permitted angle in degrees.
local TriSpec = {}

Document methods immediately before their definitions:

--- Set the maximum triangle area.
---@param area number Maximum permitted area.
---@return TriSpec self
function TriSpec:max_area(area)

Use aliases for constrained values and unions:

---@alias Scheme
---| "uds" # First-order upwind.
---| "cds" # Central differencing.

- Prefer stable, meaningful public type names.
- Do not invent inheritance or elaborate generic hierarchies.
- Use compound types such as Type[], table<string, Type>, Type | nil, and fun(x: number): Type only when they clarify the API.
- Functions returning a documented class are treated as constructors automatically.


# File headers

Every Lua source file should start with a filename, description,
author, and date:

-- lua/jnl/example.lua - Short module description
-- <your@email.llm> // 2026-06-11

- Use <your@email.llm> for newly generated files until a human reviews and takes authorship.
- Preserve an existing human author line when modifying a file.


# Section headers

Use this exact style for major sections:

--
-- Header title
--

Do not add long ASCII lines, boxes, repeated equals signs, or other
decorative separators.


# British English

Use British English in comments, documentation, identifiers where
appropriate, and user-facing output.

- colour, not color
- centre, not center
- neighbour, not neighbor
- initialise, not initialize
- organise, not organize
- optimise, not optimize


# Tests

- Add tests for public behaviour when changing implementation.
- Use test.harness with h.describe, h.it, and h.expect.
- Group tests by behaviour rather than private implementation function.
- Prefer small, explicit assertions over large snapshot tests.
- For source scanners and parsers, use compact neighbouring fixture modules containing representative syntax.
- Do not test private parsing helpers directly unless they form an intentionally stable interface.


# Writing general JNL scripts

- Use the same clean, shallow style as library code.
- Prefer named functions over large anonymous callbacks.
- Write scripts as readable procedures rather than large JSON-like configuration tables.
- Expose useful intermediate geometry, meshes, specifications, fields, and results for interactive exploration.
- Provide at least one safe no-argument function a new user can call immediately.
- Print a short post-load message identifying the main entry point.
- Do not start expensive computation merely by loading a script.


# REPL usage

- Make showcase scripts friendly to the JNL REPL.
- For a plain REPL script, use local repl = require("jnl.repl").new().
- For an FVM study, prefer local study = require("jnl.fvm.study").new("Title").
- Register values and helpers with repl:register or study:expose when useful.
- End a plain script with return repl:run().
- End a Study script with return study:repl().
- Remember that user-entered REPL expressions use Fennel even when the loaded script is Lua.
- Give Fennel-friendly invocation examples such as (demo), (show-mesh), and (run {:scheme "cds"}).


# Fennel style

- Prefer Lua for substantial source and showcase files.
- Use Fennel syntax for user-facing REPL examples.
- Use ;; for Fennel documentation-style comments when appropriate.
- Keep Fennel expressions shallow and readable.
- Use threading macros only when they materially improve clarity.
- Pass option tables in the same shape expected by the Lua API.


# CFD case structure

- Write CFD cases as readable Lua scripts rather than declarative configuration blobs.
- Separate metadata, defaults, geometry, mesh, physics, algorithm, boundary conditions, outputs, and entry points into short sections.
- Use ordinary named functions so users can call, copy, modify, loop over, sweep, or optimise each stage.
- List defaults and design variables near the top of the file.
- Provide a safe no-argument entry point such as demo, instructions, or show_mesh.


# CFD Study API

- Use jnl.fvm.study when it makes a case easier to inspect and operate interactively.
- Keep important geometry, physics, solver, and post-processing logic in ordinary functions rather than hiding it inside the Study object.
- Use study:defaults for solver settings and fixed run configuration.
- Use study:design for variables intended for sweeps, optimisation, or uncertainty analysis.
- Prefer concise registrations such as study:output, study:figure, and study:table.
- Use generated Study registration descriptions unless an explicit description adds useful information.
- Register mesh, registry, algorithm, and boundary-condition builders when standard inspectors depend on them.


# CFD evaluation and results

- Provide an evaluate or run function accepting optional overrides and returning a predictable result table.
- Keep evaluation composable so it can be used directly, in loops, sweeps, optimisation, and uncertainty studies.
- Use study:default_evaluate before adding case-specific post-processing when using a custom Study evaluator.
- Read runtime values from the merged result options rather than querying mutable Study state during plotting or writing.
- Do not write files without an explicit path supplied by the caller.


# CFD figures and output

- Put figure construction in named local functions that take a result and return a Figure.
- Use study:figure when plotted and written output represent the same data.
- Use study:table for richer tabular output not represented directly by a figure.
- Keep custom writers for VTK, mesh formats, and other non-figure output.
- Use established JNL plotting and profile helpers rather than manually reproducing their behaviour.


# Parametric studies

- Make design variables explicit and pass them through geometry, meshing, physics, evaluation, and post-processing.
- Use ordinary Lua loops for sweeps when they are clearer than configuration tables.
- Use cached Study runs where available so repeated workflows remain idempotent.
- Return consistent result objects from individual runs so analysis code does not depend on execution order.



# Complete API reference


## jnl.core.expr

   (no module description)

   Functions

      jnl.core.expr.add(...: number|string|Expr) -> Expr

      jnl.core.expr.cV() -> Expr
         Cell volume

      jnl.core.expr.const(value: number) -> Expr

      jnl.core.expr.cx() -> Expr
         Cell centre x coordinate.

      jnl.core.expr.cy() -> Expr
         Cell centre y coordinate.

      jnl.core.expr.div(a: number|string|Expr, b: number|string|Expr) -> Expr

      jnl.core.expr.expl(field: string) -> Expr
         Explicit (lagged) value of field, held fixed during inner iterations.

      jnl.core.expr.mul(...: number|string|Expr) -> Expr

      jnl.core.expr.neg(a: number|string|Expr) -> Expr

      jnl.core.expr.pow(base: number|string|Expr, exp: number|string|Expr) -> Expr

      jnl.core.expr.pretty(e: Expr|number, parent_prec: integer|nil, is_right_child:
      boolean|nil) -> string
         Render an expression to a human-readable string. Exposed as both M.pretty(e)
         and Expr:pretty() — the free function form is used internally for recursive
         calls with explicit precedence arguments.

      jnl.core.expr.prev(field: string) -> Expr
         Value of field from the previous time step.

      jnl.core.expr.prime(field: string) -> Expr
         Explicit (linearised) value of field at the previous outer iteration.

      jnl.core.expr.sub(a: number|string|Expr, b: number|string|Expr) -> Expr

      jnl.core.expr.sym(name: string) -> Expr


## jnl.core.glyphs

   (no module description)

   Functions

      jnl.core.glyphs.partial(expr_str, axis_str)

      jnl.core.glyphs.partial_prefix()

      jnl.core.glyphs.subscript(axis)

      jnl.core.glyphs.superscript_int(n)


## jnl.core.optional

   (no module description)

   Functions

      jnl.core.optional.require(modname: string) -> table
         Require a module, returning a deferred-error stub if unavailable.


## jnl.core.sim

   (no module description)

   Functions

      jnl.core.sim.new(runner, alg, opts)


## jnl.core.validation

   (no module description)

   Functions

      jnl.core.validation.identifier(s, label)

      jnl.core.validation.in_enum(set, name, ctx)

      jnl.core.validation.in_set(set, name, ctx)

      jnl.core.validation.keys(t)

      jnl.core.validation.nonempty(t, label)

      jnl.core.validation.norm(name, label)

      jnl.core.validation.oneof(val, options, label)

      jnl.core.validation.typeof(val, t, label)


## jnl.explore.pareto

   (no module description)

   Functions

      jnl.explore.pareto.linspace(lo, hi, n)

      jnl.explore.pareto.pareto(name)

      jnl.explore.pareto.uniform(lo, hi)

      jnl.explore.pareto.values(values)

      jnl.explore.pareto.values_from(records, name)


## jnl.explore.stat

   (no module description)

   Functions

      jnl.explore.stat.count(xs)

      jnl.explore.stat.max(xs)

      jnl.explore.stat.mean(xs)

      jnl.explore.stat.median(xs)

      jnl.explore.stat.min(xs)

      jnl.explore.stat.quantile(xs, q)

      jnl.explore.stat.quartiles(xs)

      jnl.explore.stat.std(xs, sample)

      jnl.explore.stat.sum(xs)

      jnl.explore.stat.summary(xs)

      jnl.explore.stat.variance(xs, sample)


## jnl.explore.uq

   (no module description)

   Functions

      jnl.explore.uq.choice(values)

      jnl.explore.uq.constant(value)

      jnl.explore.uq.discrete(pairs)

      jnl.explore.uq.lognormal(mean, rel_sd)

      jnl.explore.uq.monte_carlo(name)

      jnl.explore.uq.normal(mean, sd)

      jnl.explore.uq.run(model_fn, inputs, n, opts)

      jnl.explore.uq.uniform(lo, hi)


## jnl.fvm

   (no module description)

   Functions

      jnl.fvm.ctx_new(mesh, n_fields, n_face_fields, n_systems, opts)


## jnl.fvm.algorithm

   Configure and drive a finite-volume solution algorithm.

   Typical usage:

   local alg = Algorithm.new("simple") :loop(function(b) b:solve("U") b:solve("p")
   b:correct("U") end, 200) :converge(Rules.residual_below("*", 1e-4))
   :guard(Rules.nan_guard())

   alg:set_cfg("U", "relax", 0.7) alg:set_cfg("p", "relax", 0.3)


## jnl.fvm.bc

   Construct boundary condition descriptors for FVM cases.

   There are two usage patterns:

   Direct descriptors — build a plain table per field and attach patch names manually:

   bcs = { p = { { patch = "east", bc.pressure_outlet(0.0) } }, }

   Set builder (recommended) — fluent API that enforces field names and patch strings:

   bcs = bc.new_set() :vector("U") :on("south", bc.no_slip()) :on("north",
   bc.moving_wall(1.0, 0.0)) :scalar("p") :on("east", bc.pressure_outlet(0.0))
   :on("south", bc.nograd()) :build()

   Both forms are accepted by Case.new().

   Functions

      jnl.fvm.bc.dirichlet(value: number) -> BCDescriptor
         Prescribe a fixed scalar value on a boundary face.
         value               Prescribed value.

      jnl.fvm.bc.dirichlet_v(ux: number, uy: number) -> BCDescriptor
         Prescribe fixed x and y velocity components on a boundary face.
         ux                  x-component value.
         uy                  y-component value.

      jnl.fvm.bc.fixed(value: number) -> BCDescriptor
         Alias for BC.dirichlet. Clearer intent for fixed temperature or concentration.
         value               Prescribed value.

      jnl.fvm.bc.free_slip() -> BCDescriptor
         Free-slip or symmetry plane: zero normal velocity, zero tangential gradient.

      jnl.fvm.bc.inlet(ux: number, uy: number) -> BCDescriptor
         Prescribed inlet velocity.
         ux                  x-component of inlet velocity.
         uy                  y-component of inlet velocity.

      jnl.fvm.bc.moving_wall(ux: number, uy?: number) -> BCDescriptor
         Moving wall, e.g. the lid in Couette or lid-driven cavity flow.
         ux                  Wall x-velocity.
         uy                  Wall y-velocity; defaults to zero.

      jnl.fvm.bc.neumann(grad_n?: number) -> BCDescriptor
         Prescribe the normal gradient of a scalar field on a boundary face.
         grad_n              Normal gradient; defaults to zero (zero-flux).

      jnl.fvm.bc.neumann_v(ux_gn?: number, uy_gn?: number) -> BCDescriptor
         Prescribe the normal gradients of both velocity components.
         ux_gn               x-gradient; defaults to zero.
         uy_gn               y-gradient; defaults to zero.

      jnl.fvm.bc.new_set() -> BCSetBuilder
         Create a fluent BC set builder.

         Typical usage:

         local bcs = bc.new_set() :vector("U") :on(E.PATCH.SOUTH, bc.no_slip())
         :on(E.PATCH.NORTH, bc.moving_wall(1.0, 0.0)) :scalar("p") :on(E.PATCH.EAST,
         bc.pressure_outlet(0.0)) :on(E.PATCH.WEST, bc.nograd()) :build()

      jnl.fvm.bc.no_slip() -> BCDescriptor
         No-slip viscous wall: zero velocity in both components.

      jnl.fvm.bc.nograd() -> BCDescriptor
         Zero normal gradient. The most common outlet or symmetry scalar condition.

      jnl.fvm.bc.nt(nkind: integer, nval: number, tkind: integer, tval: number) ->
      BCDescriptor
         Normal/tangential split condition for a vector field.

         Use BC.N / BC.D / BC.R for the kind arguments.
         nkind               Normal component kind (BC.N | BC.D | BC.R).
         nval                Normal component value.
         tkind               Tangential component kind (BC.N | BC.D | BC.R).
         tval                Tangential component value.

      jnl.fvm.bc.outlet() -> BCDescriptor
         Zero-gradient advective outlet.

      jnl.fvm.bc.pressure_outlet(value?: number) -> BCDescriptor
         Fix the pressure at a boundary face.
         value               Reference pressure; defaults to zero.

      jnl.fvm.bc.robin(a: number, b: number, c: number) -> BCDescriptor
         General Robin condition: a*phi + b*(dphi/dn) = c.
         a                   Coefficient on phi.
         b                   Coefficient on dphi/dn.
         c                   Right-hand side value.


## jnl.fvm.case

   Run a finite-volume simulation case step by step or to completion.

   A Case bundles a physics registry, algorithm, mesh, and boundary conditions. It
   compiles them once at construction, allocates field storage lazily on the first step
   or run, and drives the solver via a coroutine that yields CaseEvent values at each
   iteration boundary and linear solve.

   Typical workflow:

   local case = Case.new(reg, alg, mesh, bcs) case:run() local p = case:field("p")


## jnl.fvm.compiler

   FVM compilation pipeline.

   The three phases are deliberately exposed so host code (case builders, tests, REPL
   inspection) can run them individually. Use compile() when you want the full pipeline
   in one call.

   Functions

      jnl.fvm.compiler.compile(alg: Algorithm, reg: Registry)
         Run the full compilation pipeline in order.

      jnl.fvm.compiler.elaborate(alg: Algorithm, reg: Registry)
         Discover intermediate fields and build the resource manifest.

         Must run after expand(). Sets alg.elaborated (intermediate field registry and
         face-flux map) and alg.manifest (cell, face, system, and scratch allocations).

      jnl.fvm.compiler.expand(alg: Algorithm, reg: Registry)
         Expand an algorithm into an abstract three-phase schedule.

         Populates alg.pre, alg.main, and alg.post with abstract instructions (fill,
         evaluate, solve, correct, clip, zero). Abstract ops are not yet expanded to
         concrete FVM assembly.

      jnl.fvm.compiler.lower(alg: Algorithm, reg: Registry)
         Lower the abstract schedule to concrete FVM assembly instructions.

         Must run after elaborate(). Replaces abstract solve/evaluate/correct ops in
         alg.pre, alg.main, and alg.post with concrete instruction sequences.

      jnl.fvm.compiler.lower_equation(field: string, entry: table, elab: table) ->
      Inst[], table
         Lower a single registry entry's equation to a concrete instruction list.

         Useful for inspecting what assembly a specific field equation produces without
         running the full algorithm pipeline. The alg passed here must already have
         alg.elaborated set (i.e. elaborate() must have run).

         Returns the instruction list and a small info table so callers can make
         assertions without reimplementing instruction walks.
         field               Field name being solved.
         entry               Registry entry (from reg:entry(field)).
         elab                Elaboration result (alg.elaborated).
         return 1            instructions
         return 2            info { has_div_cells, has_ghost_fills, n_instructions }


## jnl.fvm.preset

   (no module description)

   Functions

      jnl.fvm.preset.alg.pimple(opts?: AlgOpts) -> Algorithm
         PIMPLE (PISO within a SIMPLE outer loop).

         PISO-style inner pressure corrections within a SIMPLE outer convergence loop.
         More robust than either alone for hard-to-converge flows; also the standard for
         unsteady cases that need to reach steady state efficiently. max_iters controls
         outer correctors; n_correctors controls inner sweeps.

      jnl.fvm.preset.alg.piso(opts?: AlgOpts) -> Algorithm
         PISO (Pressure Implicit with Splitting of Operators).

         Multiple pressure-correction steps per momentum solve. Suited to unsteady
         time-accurate flows; no velocity under-relaxation. Pair with
         Case:run_transient() or begin_timestep() / end_timestep().
         opts                n_correctors controls inner correction sweeps (default 2).

      jnl.fvm.preset.alg.simple(opts?: AlgOpts) -> Algorithm
         SIMPLE (Semi-Implicit Method for Pressure-Linked Equations).

         One pressure correction per outer iteration. Standard choice for steady laminar
         flows. Velocity is under-relaxed; pressure is updated explicitly.

      jnl.fvm.preset.reg.ns(opts?: RegOpts) -> Registry
         Laminar incompressible Navier-Stokes with convection.

         Uses Rhie-Chow momentum-weighted interpolation for the convective flux.

      jnl.fvm.preset.reg.stokes(opts?: RegOpts) -> Registry
         Stokes (viscous, no convection) incompressible flow.

         Exact for plane Couette and Poiseuille flow. Prefer over ns when convective
         acceleration is negligible: avoids the mwi outer-product assembly.


## jnl.fvm.rules

   Convergence and divergence criterion constructors for FVM cases.

   Criterion objects are plain tables passed to Algorithm:converge() and
   Algorithm:guard() before the Case is constructed:

   alg:converge(Rules.residual_below("*", 1e-4)) alg:guard(Rules.nan_guard())
   alg:guard(Rules.norm_above("p", 1e8))

   The wildcard field `"*"` expands at runtime to every field that has produced residual
   telemetry, so `residual_below("*", tol)` is the standard all-fields convergence
   criterion.

   Functions

      jnl.fvm.rules.assert_alg_criteria(sage: table, alg: Algorithm)
         Post all convergence and divergence criteria from an algorithm as Sage facts.

         Called automatically by Case:reset(). Invoke directly only when managing a Sage
         instance outside a Case.
         sage                Sage instance.
         alg                 Algorithm carrying convergence and divergence criterion
                             lists.

      jnl.fvm.rules.change_below(field: string, threshold: number, n_consec?: integer)
      -> ConvCrit
         Convergence criterion: field L2 change below threshold for n_consec consecutive
         iterations.
         field               Field name or "*".
         threshold           Change threshold.
         n_consec            Consecutive iterations required; defaults to 1.

      jnl.fvm.rules.nan_guard(field?: string) -> DivCrit
         Divergence guard: stop when a NaN is detected in a field.
         field               Field name or "*"; defaults to "*" (any field).

      jnl.fvm.rules.norm_above(field: string, threshold?: number) -> DivCrit
         Divergence guard: stop when field L2 norm exceeds threshold.

         Also fires on NaN, so this catches both blowup and breakdown before the
         residual has a chance to diverge.
         field               Field name or "*".
         threshold           Norm limit; defaults to 1e10.

      jnl.fvm.rules.residual_above(field: string, threshold?: number) -> DivCrit
         Divergence guard: stop when field residual exceeds threshold.
         field               Field name or "*".
         threshold           Residual limit; defaults to 1e10.

      jnl.fvm.rules.residual_below(field: string, threshold: number, n_consec?: integer)
      -> ConvCrit
         Convergence criterion: field residual below threshold for n_consec consecutive
         iterations.

         Pass `"*"` as the field to require all fields with residual telemetry to
         converge.
         field               Field name or "*".
         threshold           Residual threshold.
         n_consec            Consecutive iterations required; defaults to 1.

      jnl.fvm.rules.stopping_ruleset() -> table
         Return the standard FVM stopping ruleset.

         Registers convergence and divergence checking rules with a Sage instance. Case
         adds this ruleset automatically; call it explicitly only when constructing a
         Sage outside a Case.
         return 1            ruleset


## jnl.fvm.study

   (no module description)

   Functions

      jnl.fvm.study.new(title)


## jnl.fvm.vtk

   (no module description)

   Functions

      jnl.fvm.vtk.write(path, mesh, scalars, vectors)

      jnl.fvm.vtk.writer(path, mesh)


## jnl.geo2d.curve

   Low-level 2D curve primitives, transformations, and sampling utilities.

   Curve2D objects are immutable value types produced by constructors and
   transformations here, or retrieved from a Pen via :get() and :build().

   For constructing domain boundaries with named patches, prefer the Pen API
   (jnl.geo2d.pen). Use this module for: - simple standalone shapes (circle, rectangle)
   used as hole boundaries; - post-construction transformations (translate, scale,
   rotate, map); - sampling points for analysis or comparison; - discretising curves
   onto a PSLG for custom meshing.

   Functions

      jnl.geo2d.curve.between(p0: Point2D, p1: Point2D) -> Curve2D
         Construct a line from two point tables.

      jnl.geo2d.curve.circle(centre: Point2D, radius: number, opts?: { angle0:number?,
      clockwise:boolean? }) -> Curve2D
         Construct a complete circle as a chain of four exact arcs.

         The seam is at angle0 and the orientation is counter-clockwise unless clockwise
         is true.

      jnl.geo2d.curve.circular_arc(centre: Point2D, radius: number, theta0: number,
      theta1: number) -> Curve2D
         Construct a circular arc from point-like centre and angular limits.

      jnl.geo2d.curve.closed_polyline(points: Point2D[], eps: number?) -> Curve2D
         Construct a closed polyline.

         The first point is appended when it is not already repeated at the end.

      jnl.geo2d.curve.discretise(curve: Curve2D, marker: integer?, opts?: table) -> PSLG
         Discretise a curve into a new PSLG.

      jnl.geo2d.curve.discretise_onto(curve: Curve2D, pslg: PSLG, marker: integer?,
      opts?: { n:integer?, distribution:Dist1D?, closed:boolean?, eps:number? }) ->
      integer[]
         Discretise an open curve onto a PSLG.
         return 1            nodes

      jnl.geo2d.curve.join(curves: (Curve2D|nil)[]) -> Curve2D
         Construct a chain after removing nil entries.

      jnl.geo2d.curve.map(curve: Curve2D, fn: fun(x:number, y:number): number, number,
      opts?: { n:integer?, distribution:Dist1D?, mode:Curve2DSampleMode? }) -> Curve2D

      jnl.geo2d.curve.rectangle(x0: number, y0: number, x1: number, y1: number) ->
      Curve2D
         Construct a rectangular closed boundary as a curve chain.

         The resulting orientation is counter-clockwise.

      jnl.geo2d.curve.rotate(curve: Curve2D, angle: number, centre: Point2D?, opts?:
      table) -> Curve2D

      jnl.geo2d.curve.sample(curve: Curve2D, n: integer, distribution: Dist1D?) ->
      Point2D[]
         Sample a curve using arc-length parameterisation by default.

      jnl.geo2d.curve.sample_closed(curve: Curve2D, n: integer, distribution: Dist1D?)
      -> Point2D[]
         Sample a closed curve without repeating the final seam point.

      jnl.geo2d.curve.scale(curve: Curve2D, sx: number, sy: number?, opts?: table) ->
      Curve2D

      jnl.geo2d.curve.through(points: Point2D[]) -> Curve2D
         Construct an open polyline from points.

      jnl.geo2d.curve.translate(curve: Curve2D, dx: number, dy: number, opts?: table) ->
      Curve2D

   Values

      jnl.geo2d.curve.arc: fun(cx:number, cy:number, radius:number, theta0:number,
      theta1:number): Curve2D
      jnl.geo2d.curve.chain: fun(curves:Curve2D[]): Curve2D
      jnl.geo2d.curve.cosine_both: fun(): Dist1D
      jnl.geo2d.curve.geom_end: fun(ratio:number): Dist1D
      jnl.geo2d.curve.geom_start: fun(ratio:number): Dist1D
      jnl.geo2d.curve.line: fun(x0:number, y0:number, x1:number, y1:number): Curve2D
      jnl.geo2d.curve.polyline: fun(points:Point2D[]): Curve2D
      jnl.geo2d.curve.uniform: fun(): Dist1D


## jnl.geo2d.domain

   Construct meshable Domain2D objects from closed Pen shapes.

   The primary entry point is from_pen(), which converts a tagged Pen into a Domain2D
   and a MarkerRegistry. Holes and interior regions are added to the Domain2D
   afterwards:

   local curve = require("jnl.geo2d.curve") local d, reg = domain.from_pen(p)

   -- Add a circular hole; seed must be a point strictly inside the hole. local hole =
   curve.circle({0.5, 0.5}, 0.1) d:add_hole("cylinder", reg:get("cylinder"), hole, {0.5,
   0.5})

   Functions

      jnl.geo2d.domain.from_pen(p: Pen, opts: Domain2DOpts?) -> Domain2D, MarkerRegistry
         Construct a `Domain2D` from a closed `Pen`.


## jnl.geo2d.pen

   Fluent pen/turtle API for building closed domain boundaries.

   A Pen traces a 2D shape step-by-step, tagging each segment with a BC name and
   optionally attaching discretisation hints. Pass the finished pen to domain.from_pen()
   to produce a meshable Domain2D.

   Typical workflow:

   local pen = require("jnl.geo2d.pen") local domain = require("jnl.geo2d.domain")

   local p = pen.new() :at(0, 0) :north(1) :tag("inlet") :east(2) :tag("top") :south(1)
   :tag("outlet") :close() :tag("wall") local d, reg = domain.from_pen(p)

   Holes and interior regions are added to the Domain2D afterwards using
   Domain2D:add_hole() and Domain2D:add_region().

   Functions

      jnl.geo2d.pen.new() -> Pen
         Create a new pen at an unset position.


## jnl.gp

   (no module description)

   Functions

      jnl.gp.cycler()

      jnl.gp.figure(opts)

      jnl.gp.histogram(values, opts)

      jnl.gp.sample(fn, x0, x1, n)

      jnl.gp.scatter(xs, ys, opts)

      jnl.gp.series(xs, ys, opts)

      jnl.gp.write_csv(path, xs_or_series, ys, header)
         Write one or more series to a CSV. - M.write_csv(path, series_list) -
         M.write_csv(path, xs, ys, header?)


## jnl.gp.compare

   (no module description)

   Functions

      jnl.gp.compare.error_norms(comparison)

      jnl.gp.compare.figure(numerical, reference, opts)

      jnl.gp.compare.profile(coord, value, opts)

      jnl.gp.compare.sample_at_reference(numerical, reference)

      jnl.gp.compare.save(path, numerical, reference, opts)

      jnl.gp.compare.show(numerical, reference, opts)

      jnl.gp.compare.write_comparison_csv(path, comparison, opts)

      jnl.gp.compare.write_profile_csv(path, numerical, reference, opts)


## jnl.gp.mesh

   (no module description)

   Functions

      jnl.gp.mesh.line_profile(mesh, field_vec, axis, value, opts)

      jnl.gp.mesh.patch_profile(mesh, field_vec, patch_name, coord, opts)


## jnl.mesh2d

   (no module description)

   Functions

      jnl.mesh2d.patch_list(mesh: Mesh2D) -> PatchInfo[]
         Return a normalised list of patches from a mesh.

         Each entry renames `marker` to `id` for consistency with BC tables.

      jnl.mesh2d.patch_lookup(mesh: Mesh2D) -> table<integer|string, PatchInfo>
         Return a table indexed by both integer marker and name string.

         Allows lookup by either `t[marker]` or `t["name"]`.

      jnl.mesh2d.patch_name_list(mesh: Mesh2D) -> string[]
         Return an ordered list of patch name strings.

      jnl.mesh2d.patch_name_set(mesh: Mesh2D) -> table<string, true>
         Return a set of patch name strings present in the mesh.


## jnl.mesh2d.block

   Fluent builders for single structured blocks and multi-block grids.

   Single block:

   local mesh2d = require("jnl.mesh2d") local mesh, err = mesh2d.block(33, 33)
   :south(curve.line(0,0, 1,0), { marker = WALL }) :east( curve.line(1,0, 1,1), { marker
   = OUTLET }) :north(curve.line(0,1, 1,1), { marker = TOP }) :west( curve.line(0,0,
   0,1), { marker = INLET }) :tfi() :build()

   Multi-block grid:

   local E = mesh2d.edges local g = mesh2d.grid() local b0 = g:block(33, 33) local b1 =
   g:block(33, 33) g:join(b0, E.E, b1, E.W) b0:south(...):east(...):north(...):west(...)
   b1:south(...):east(...):north(...) -- west is auto-populated local mesh, err =
   g:build()

   O-mesh cyclic topology:

   local blocks = { g:block(33,33), g:block(33,33), g:block(33,33), g:block(33,33) }
   g:join_ring(blocks, E.E, E.W)

   Functions

      jnl.mesh2d.block.block(ni: integer, nj: integer) -> BlockBuilder
         Create a standalone structured block builder.

         ni is the number of grid points along the south and north edges. nj is the
         number of grid points along the east and west edges.

      jnl.mesh2d.block.grid() -> GridBuilder
         Create a multi-block structured grid builder.


## jnl.mesh2d.cartesian

   Build axis-aligned Cartesian meshes with standard NESW patch names.

   Functions

      jnl.mesh2d.cartesian.build(width: number, height: number, nx: integer, ny:
      integer) -> Mesh2D?, string?
         Build a Cartesian mesh with nx * ny cells over a width * height domain.
         nx                  Cell count in x.
         ny                  Cell count in y.
         return 1            mesh
         return 2            err


## jnl.mesh2d.edges

   NESW edge direction constants and patch name strings shared across cartesian,
   structured block, and triangulated mesh modules.

   Integer direction constants (S/E/N/W) are used by the block and grid builders. String
   patch names (PATCH.*) are used as BC identifiers on any mesh type.


## jnl.mesh2d.tri

   Fluent specification builder and entry points for Triangle-backed unstructured mesh
   generation.

   Typical workflow:

   local pslg = curve.discretise(domain_curve, marker) local mesh = tri.spec()
   :from_domain_reg(reg) :min_angle(28) :resolution(pslg, 0.05) :triangulate(pslg)

   For Domain2D input use tri.from_domain()

   Functions

      jnl.mesh2d.tri.from_domain(domain: Domain2D, spec: TriSpecBuilder, opts?: {
      n:integer? }) -> Mesh2D?, string?
         Triangulate a Domain2D directly.
         return 1            mesh
         return 2            err

      jnl.mesh2d.tri.pslg_from_domain(domain: Domain2D, opts?: { n:integer? }) -> PSLG?,
      string?
         Lower a Domain2D to a PSLG suitable for triangulation.

         Samples each boundary curve at n points, adds nodes and constrained edges to a
         new PSLG, and inserts hole and region seeds.
         return 1            pslg
         return 2            err

      jnl.mesh2d.tri.spec() -> TriSpecBuilder
         Create a triangulation specification.


## jnl.nabla.equation

   Symbolic equation pairing a left-hand side and right-hand side expression.

   Equations are normally constructed with `Node:equals(rhs)` or `Equation.new(lhs,
   rhs)`.


## jnl.nabla.eval

   (no module description)

   Functions

      jnl.nabla.eval.compile(node: Node, bindings: table<string, userdata|number>)
         Compile a scalar nabla Node against a bindings map. Returns a compiled ud
         object with :eval(pool, n).
         node                rank-0 nabla node

      jnl.nabla.eval.eval(node, bindings, pool, n)

      jnl.nabla.eval.scratch_depth(node)


## jnl.nabla.node

   Expression graph node for the Nabla symbolic system. All constructor functions return
   a Node; arithmetic operators are overloaded. Nodes are immutable once constructed —
   all operations return new nodes.


## jnl.nabla.registry

   Declare fields, constants, governing equations, and derived expressions for a
   symbolic physics model.

   A registry stores named symbolic fields in declaration order. Field declarations
   return injected `Node` instances with chainable methods such as `governed_by`,
   `defined_as`, `prescribed`, and `initial`.


## jnl.repl

   Provide a configurable Fennel REPL with a convenient default instance.

   Functions

      jnl.repl.command(name: string, fn: fun(repl: jnl.repl.Repl, arg: string), usage?:
      string, doc?: string)
         Register a comma command on the default REPL.
         name                Command name without the comma.
         usage               Displayed command usage.
         doc                 Help text.

      jnl.repl.default() -> jnl.repl.Repl
         Return the process-wide default REPL, creating it when needed.
         return 1            repl

      jnl.repl.is_cancelled() -> boolean
         Return true when Ctrl-C has requested cancellation of active evaluation.
         return 1            cancelled

      jnl.repl.llm(opts?: table)
         Print the complete JNL coding context for a language model.
         opts                Context rendering options.

      jnl.repl.llm_string(opts?: table) -> string
         Return the complete JNL coding context for a language model.
         opts                Context rendering options.
         return 1            text

      jnl.repl.new(opts?: table) -> jnl.repl.Repl
         Create an independent REPL instance.
         opts                Construction options.
         return 1            repl

      jnl.repl.pp(value: any, opts?: table) -> any
         Pretty-print a value using the default REPL printer.
         value               Value to print.
         opts                Fennel view options.
         return 1            value

      jnl.repl.register(name: string, value: any, doc?: ReplDocSpec) -> any
         Expose a value as a global and register it with the default REPL help system.

         With no documentation argument, JNL attempts to find a uniquely matching
         source-derived API description. Pass literal text, `{ from = "module.symbol"
         }`, or `false` to suppress documentation lookup.
         name                User-facing global name.
         value               Value to expose.
         doc                 Documentation source.
         return 1            value

      jnl.repl.run()
         Start the default REPL.

         Calling this from a script marks the REPL as started in the host program, so
         `--repl` does not start another REPL after the script returns.

      jnl.repl.script_summary(script_path: string)
         Print globals introduced by a script.
         script_path         Executed script path.

      jnl.repl.special(name: string, value: any, label?: string|false) -> any
         Store a value in a named special on the default REPL.
         name                Name such as `*last-run*`.
         value               Value to store.
         label               Confirmation label; false suppresses output.
         return 1            value

      jnl.repl.usage(spec: ReplUsageSpec)
         Register study-specific usage on the default REPL.
         spec                Usage text or provider.


## jnl.repl.printer

   Format wrapped, Markdown-like text for terminals and generated documents.

   Functions

      jnl.repl.printer.fmt.bullet(text: any, opts?: table) -> string
         Return a Markdown-style bullet.
         text                Bullet text.
         opts                Formatting options, including `indent`.
         return 1            text

      jnl.repl.printer.fmt.header(text: any, level?: integer) -> string
         Return a Markdown-style heading with surrounding whitespace.
         text                Heading text.
         level               Heading level from 1 to 6.
         return 1            text

      jnl.repl.printer.fmt.indent(text: any, count?: integer) -> string
         Indent every line of a text block.
         text                Text to indent.
         count               Number of spaces; defaults to 2.
         return 1            text

      jnl.repl.printer.fmt.kv(key: any, value: any, opts?: table) -> string
         Return a simple key-value line.
         key                 Key or label.
         value               Value text.
         opts                Formatting options, including `indent` and `separator`.
         return 1            text

      jnl.repl.printer.fmt.rule(opts?: table) -> string
         Return a Markdown horizontal rule.
         opts                Formatting options, including `indent`.
         return 1            text

      jnl.repl.printer.new(opts?: table) -> Printer
         Create a buffered or callback-backed printer.
         opts                Options containing `width` and optional `out`.
         return 1            printer


## jnl.repl.study

   (no module description)

   Functions

      jnl.repl.study.new(title)


## jnl.sage

   (no module description)

   Functions

      jnl.sage.match(pattern)

      jnl.sage.match_all(...)

      jnl.sage.match_any(...)

      jnl.sage.new()


## jnl.ui

   Visualiser window management for meshes and scalar fields.

   There are two distinct usage phases with different recovery semantics:

   Setup phase — display_domain and display_mesh spawn a new window automatically if
   the current default has been closed:

   local ui = require("jnl.ui") ui.display_domain(domain) -- preview geometry before
   meshing ui.display_mesh(mesh) -- send topology once mesh is built ui.set_vector("U",
   "U_x", "U_y") ui.view_field("U")

   Live phase — set_field does NOT recover; call it inside a solve loop only after
   display_mesh has succeeded. It returns false silently if the window is closed
   mid-run:

   -- inside solve loop: ui.set_field("p", ctx:field_vec("p")) ui.set_field("U_x",
   ctx:field_vec("U_x")) ui.set_field("U_y", ctx:field_vec("U_y"))

   Handles are optional everywhere; pass one explicitly to manage multiple windows, or
   omit to use the process-wide default.

   Functions

      jnl.ui.close(handle?: jnl.ui.Handle)
         Close the given handle (or the default), removing it from the default slot.

      jnl.ui.default() -> jnl.ui.Handle
         Return (or lazily spawn) the process-wide default handle.

      jnl.ui.display_domain(domain: Domain2D, handle?: jnl.ui.Handle) -> boolean
         Send a domain2d object for boundary display. Spawns a new default window if the
         current one is dead.

      jnl.ui.display_mesh(mesh: Mesh2D, handle?: jnl.ui.Handle) -> boolean
         Send mesh topology. Spawns a new default window if the current one is dead.

      jnl.ui.set_field(name: string, data: VecUD, handle?: jnl.ui.Handle) -> boolean
         Push a scalar field update. No recovery — call during a live solve loop after
         display_mesh has already succeeded. Returns false silently if the window has
         been closed (e.g. user dismissed it mid-run).
         name                field name, e.g. "p" or "U_x"
         data                values; length must match mesh vertex or cell count

      jnl.ui.set_vector(name: string, fx: string, fy: string, handle?: jnl.ui.Handle) ->
      boolean
         Associate two scalar fields as a named vector (for magnitude rendering).
         name                e.g. "U"
         fx                  e.g. "U_x"
         fy                  e.g. "U_y"

      jnl.ui.spawn() -> jnl.ui.Handle
         Spawn a new visualiser window. The first call also sets it as the default.

      jnl.ui.view_field(name?: string, handle?: jnl.ui.Handle) -> boolean
         Switch the active field overlay. Pass nil or "" for wireframe-only.
         name                field or vector name; nil = wireframe

      jnl.ui.view_mesh(show?: boolean, handle?: jnl.ui.Handle) -> boolean
         Show or hide the mesh wireframe overlay.
         show                default true


## Types

   jnl.core.expr.Expr
      Constructors
         jnl.core.expr.add(...: number|string|Expr) -> Expr
         jnl.core.expr.cV() -> Expr
         jnl.core.expr.const(value: number) -> Expr
         jnl.core.expr.cx() -> Expr
         jnl.core.expr.cy() -> Expr
         jnl.core.expr.div(a: number|string|Expr, b: number|string|Expr) -> Expr
         jnl.core.expr.expl(field: string) -> Expr
         jnl.core.expr.mul(...: number|string|Expr) -> Expr
         jnl.core.expr.neg(a: number|string|Expr) -> Expr
         jnl.core.expr.pow(base: number|string|Expr, exp: number|string|Expr) -> Expr
         jnl.core.expr.prev(field: string) -> Expr
         jnl.core.expr.prime(field: string) -> Expr
         jnl.core.expr.sub(a: number|string|Expr, b: number|string|Expr) -> Expr
         jnl.core.expr.sym(name: string) -> Expr
      Methods

         Expr:compile(bindings: table<string, userdata>) -> Expr
            Compile this expression against a bindings table, caching the result. Must
            be called before eval(). Safe to call again to recompile with new bindings.
            bindings            Maps symbol names to vec objects
            return 1            self (for chaining)

         Expr:deps() -> string[]
            Return a sorted list of field names this expression depends on.

         Expr:eval(pool: ScratchPool, n: integer) -> VecUD
            Evaluate the compiled expression over n elements using the given scratch
            pool.
            pool                Scratch pool (from ctx:cell_pool() or ctx:face_pool())
            n                   Number of elements to evaluate over
            return 1            Result vec

         Expr:pretty() -> string

         Expr:scratch_depth() -> integer

         Expr:walk(visitor)


   jnl.fvm.algorithm.Algorithm
      Configure and drive a finite-volume solution algorithm.

      Typical usage:

      local alg = Algorithm.new("simple") :loop(function(b) b:solve("U") b:solve("p")
      b:correct("U") end, 200) :converge(Rules.residual_below("*", 1e-4))
      :guard(Rules.nan_guard())

      alg:set_cfg("U", "relax", 0.7) alg:set_cfg("p", "relax", 0.3)
      label: string?                Human-readable algorithm label.
      op: string                    Execution mode: "linear" or "loop".
      max_iters: integer            Maximum outer iterations (loop mode only).
      convergence: AlgCriterion[]   Convergence criteria added via converge().
      divergence: AlgCriterion[]    Divergence guards added via guard().
      watches: table[]              Watched fields added via watch().
      rulesets: table[]             Additional Sage rulesets.
      steps: table[]                User-specified steps before compilation.
      pre: table[]                  Compiled pre-loop instructions.
      main: table[]                 Compiled main-loop instructions.
      post: table[]                 Compiled post-loop instructions.
      config: { default: table, fields: table<string, table> }
         @Solver configuration storage.
      manifest: table?              Resource manifest populated after compilation.
      elaborated: table             
      Constructors
         jnl.fvm.preset.alg.pimple(opts?: AlgOpts) -> Algorithm
         jnl.fvm.preset.alg.piso(opts?: AlgOpts) -> Algorithm
         jnl.fvm.preset.alg.simple(opts?: AlgOpts) -> Algorithm
      Methods

         Algorithm:add_rule(rule: table) -> Algorithm
            Add a single Sage rule wrapped in a one-entry ruleset.
            rule                Sage rule.
            return 1            self

         Algorithm:add_ruleset(rs: table) -> Algorithm
            Add a complete Sage ruleset.
            rs                  Ruleset table.
            return 1            self

         Algorithm:as_cfg() -> table
            Return a Cfg view over the current configuration.
            return 1            cfg

         Algorithm:cfg(field: string, key: string) -> any
            Return the effective config value for a field and key.
            field               Field name.
            key                 Config key.

         Algorithm:compile(reg: Registry) -> Algorithm
            Compile this algorithm against a registry, populating the instruction lists.

            Equivalent to calling jnl.fvm.compiler.compile(alg, reg) directly.
            Case.new() triggers compilation automatically; call this explicitly only
            when inspecting the compiled output outside a Case.
            reg                 Physics registry.
            return 1            self

         Algorithm:converge(spec: AlgCriterion) -> Algorithm
            Add a convergence criterion.

            Accepts a `conv_crit` spec returned by Rules.residual_below(),
            Rules.change_below(), etc.
            spec                Convergence spec with kind "conv_crit".
            return 1            self

         Algorithm:default_config() -> table
            Return a Cfg view over the current configuration.
            return 1            cfg

         Algorithm:guard(spec: AlgCriterion) -> Algorithm
            Add a divergence guard.

            Accepts a `div_crit` spec returned by Rules.nan_guard(), Rules.norm_above(),
            etc.
            spec                Divergence spec with kind "div_crit".
            return 1            self

         Algorithm:instruction_listing() -> string
            Return a full FVM instruction listing after compilation.
            return 1            text

         Algorithm:linear(cb: AlgBuilderCb) -> Algorithm
            Declare a non-iterating linear sequence of steps.
            cb                  Callback specifying steps.
            return 1            self

         Algorithm:listing() -> string
            Return a human-readable abstract algorithm listing (high-level steps only).
            return 1            text

         Algorithm:loop(cb: AlgBuilderCb, max_iters?: integer) -> Algorithm
            Declare a looping outer iteration and specify its steps via a builder
            callback.

            alg:loop(function(b) b:solve("U") b:solve("p") b:correct("U") end, 200)
            cb                  Callback specifying steps executed each outer iteration.
            max_iters           Maximum outer iterations; overrides the current value.
            return 1            self

         Algorithm:new(label?: string) -> Algorithm
            Create a new algorithm.
            label               Human-readable label shown in listings.

         Algorithm:print()
            Print the abstract algorithm listing.

         Algorithm:print_instructions()
            Print the full FVM instruction listing after compilation.

         Algorithm:set_cfg(field_or_default: string, key: string, value: any) ->
         Algorithm
            Set a solver configuration value for a named field or the global default.

            Pass `"default"` as the first argument to set a fallback for all fields:

            alg:set_cfg("default", "tol", 1e-6) alg:set_cfg("U", "relax", 0.7)
            alg:set_cfg("p", "relax", 0.3)
            field_or_default    Field name, Node, or "default".
            key                 Config key (e.g. "relax", "tol", "solver",
                                "max_krylov_iters").
            value               Config value.
            return 1            self

         Algorithm:set_max_iters(n: integer) -> Algorithm
            Set the maximum number of outer iterations.
            n                   Maximum iterations.
            return 1            self

         Algorithm:summary() -> string
            Return a one-line summary of the algorithm state.
            return 1            text

         Algorithm:watch(field: string|Node, kind?: string) -> Algorithm
            Watch a named field quantity for display in convergence monitors.
            field               Field name or Node.
            kind                Quantity kind; defaults to "residual".
            return 1            self


   jnl.fvm.bc.BCSetBuilder
      Fluent builder for assembling a complete BC table.
      fields: table<string, BCFieldSpec>
      order: string[]               
      fallback: BCDescriptor?       
      Constructors
         jnl.fvm.bc.new_set() -> BCSetBuilder
      Methods

         BCSetBuilder:build() -> BCSet
            Build and return the finished BC table.

         BCSetBuilder:default(spec: BCDescriptor) -> BCSetBuilder
            Set a fallback descriptor applied to patches not covered by any :on() call.
            spec                Fallback BC descriptor.
            return 1            self

         BCSetBuilder:new() -> BCSetBuilder
            Create a new BCSetBuilder.

         BCSetBuilder:scalar(name: string) -> BCFieldSpec
            Declare a scalar field and return its field spec for patch assignment.
            name                Field name matching the registry declaration.

         BCSetBuilder:vector(name: string) -> BCFieldSpec
            Declare a vector field and return its field spec for patch assignment.
            name                Field name matching the registry declaration.


   jnl.fvm.instruction.Inst
      op: string                    
      fields: table                 
      Constructors
         jnl.fvm.compiler.lower_equation(field: string, entry: table, elab: table) ->
         Inst[], table
      Methods

         Inst:apply_correction(field, node)
            evaluates correction node expression into delta and does field:axpy(1,
            delta)

         Inst:clip(field, lo, hi)

         Inst:comment(text: string?)

         Inst:correct(field)

         Inst:ddt_f(field: string, rho: string, expr: Node?)
            rho                 Name of rho field
            expr                Optional rho-expr for display

         Inst:ddt_k(field: string, rho: number, expr: Node?)
            expr                Optional rho-expr for display

         Inst:diag_snapshot(field, out)

         Inst:div_dc(field: string, flux: string, grad_x: string, grad_y: string)
            Explicit deferred correction RHS contribution. runner no-ops if
            alg:cfg(field, "div") == "uds"|"cds"

         Inst:div_f(field: string, flux: string, coeff: string, expr: Node?)
            Implicit UDS/CDS convection assembly with named field coefficient.

         Inst:div_k(field: string, flux: string, coeff: number)
            Implicit UDS/CDS convection assembly with constant coefficient (rho)

         Inst:divergence(face_normal_field, out)

         Inst:divergence_c(field, ux, uy, integrated)

         Inst:eval_coeff(node)

         Inst:eval_expr(field, node)

         Inst:evaluate(field: string, implicit: boolean?)

         Inst:face_interp(field, out)

         Inst:face_normal(ux_face, uy_face, out)

         Inst:face_normal_c(ux, uy, out)

         Inst:fill(field: string, value: number)

         Inst:grad(field, out_x, out_y)

         Inst:lap_f(field: string, gamma: string, expr: Node?)

         Inst:lap_k(field: string, gamma: number, expr: Node?)
            expr                Optional gamma-expr for display

         Inst:lap_nonorth_f(field: string, grad_x: string, grad_y: string, coeff:
         string, expr: Node?)

         Inst:lap_nonorth_k(field: string, grad_x: string, grad_y: string, coeff:
         number, expr: Node?)

         Inst:new(op, fields)

         Inst:pclose_s_d(field: string, patch: string, value: number)

         Inst:pclose_s_n(field: string, patch: string, grad_n: number)

         Inst:pclose_s_r(field: string, patch: string, a: number, b: number, c: number)

         Inst:pfill_s_d(field: string, patch: string, value: number)

         Inst:pfill_s_n(field: string, patch: string, grad_n: number)

         Inst:pfill_s_r(field: string, patch: string, a: number, b: number, c: number)

         Inst:pfill_v_d(ux: string, uy: string, patch: string, ux_val: number, uy_val:
         number)

         Inst:pfill_v_n(ux: string, uy: string, patch: string, ux_gn: number, uy_gn:
         number)

         Inst:pfill_v_nt(ux: string, uy: string, patch: string, nkind: number, nval:
         number, tkind: number, tval: number)

         Inst:rhie_chow(Ux, Uy, p, grad_px, grad_py, diag_x, diag_y, out)

         Inst:solve(field)

         Inst:solve_linalg(field)

         Inst:sp_f(field: string, coeff: string, volumetric: boolean, expr: Node?)

         Inst:sp_fs(field: string, scale: number, src: string, volumetric: boolean,
         expr: Node?)
            volumetric          default true

         Inst:sp_k(field: string, coeff: number, volumetric: boolean)

         Inst:su_f(field: string, coeff: string, volumetric: boolean, expr: Node?)

         Inst:su_fs(field: string, scale: number, src: string, volumetric: boolean,
         expr: Node?)
            scale               scalar multiplier (negative to subtract)
            src                 name of source cell field
            volumetric          default true

         Inst:su_k(field: string, coeff: number, volumetric: boolean)

         Inst:sys_reset(field)

         Inst:tostring(indent: string?, cfg: table?)
            cfg                 falls back to INST_DEFAULTS if nil

         Inst:tostring_abstract(indent)

         Inst:under_relax(field)

         Inst:zero(field)


   jnl.geo2d.domain.MarkerRegistry
      next: integer                 
      map: table<string, integer>   
      Constructors
         jnl.geo2d.domain.from_pen(p: Pen, opts: Domain2DOpts?) -> Domain2D,
         MarkerRegistry
      Methods

         MarkerRegistry:get(name: string) -> integer


   jnl.geo2d.pen.Pen
      segs: PenSegment[]            
      tags: table<string, Curve2D>  Named segments, keyed by tag.
      Constructors
         jnl.geo2d.pen.new() -> Pen
      Methods

         Pen:arc_to(x: number, y: number, radius: number, clockwise: boolean?) -> Pen
            Arc to an absolute target point.

         Pen:arc_turn(delta_deg: number, radius: number, dist: number?) -> Pen
            Turn by delta_deg through a circular arc of the given radius, then
            optionally continue straight for dist.
            delta_deg           Signed turn angle in degrees.
            dist                Optional straight segment after the arc.

         Pen:at(x: number, y: number, initial_bearing: number?) -> Pen
            Set the starting position and optionally the initial heading.
            initial_bearing     Bearing in degrees; default 0 (north).

         Pen:bear(bearing_deg: number, dist: number) -> Pen
            Move at an absolute bearing (0 = north, clockwise) for the given distance.
            dist                Must be positive.

         Pen:build() -> Curve2D
            Build and return the complete Curve2D from all segments.

         Pen:close() -> Pen
            Draw a straight line back to the starting point.

         Pen:curve(c: Curve2D) -> Pen
            Append an externally constructed Curve2D as a segment.

            The pen position advances to the curve's endpoint. Use this when a boundary
            segment comes from coordinate data (e.g. an aerofoil surface) rather than
            pen movement.

         Pen:east(d: number) -> Pen

         Pen:endjoin(name: string) -> Pen
            Close an open :startjoin() bracket and register the compound curve.

         Pen:get(name: string) -> Curve2D
            Return a previously tagged segment as a Curve2D.

         Pen:hint(opts: PenHint) -> Pen
            Attach discretisation hints to the most recently drawn segment.

            Hints are consumed during PSLG lowering. Calling `:hint()` on an untagged
            segment is allowed; the hint is stored but will only have effect if the
            segment is later tagged before `:build()` is called — in practice, always
            call `:tag()` before `:hint()`.

            ```lua pen:at(0,0) :line_to(0, H) :tag("inlet") :hint({ n = 32 })
            :line_to(L, H) :tag("top") :line_to(L, 0) :tag("outlet") :hint({ n = 32,
            dist = curve.cosine_both() }) :close() ```

         Pen:joined(names: string[]) -> Curve2D
            Return the curve formed by joining several tagged segments in order.

            Post-hoc composition from named tags; useful when combining segments from
            different pens or in a different order than they were drawn. For inline
            grouping during pen construction prefer :startjoin()/:endjoin().

         Pen:joinlast(n: integer, name: string) -> Pen
            Join the last n segments into a named compound curve.

            Fine for stable two- or three-segment groups. Prefer :startjoin()/:endjoin()
            when the segment count may change during development.
            n                   Number of trailing segments to join (minimum 2).

         Pen:line_to(x: number, y: number) -> Pen
            Straight line to an absolute position.

         Pen:north(d: number) -> Pen

         Pen:pos() -> number, number
            Return the current pen position.
            return 1            x
            return 2            y

         Pen:south(d: number) -> Pen

         Pen:startjoin() -> Pen
            Mark the start of a compound segment group.

            All segments appended until :endjoin() are merged into a single named curve
            when :endjoin() is called. Individual :tag() calls inside the bracket still
            work and remain accessible via :get().

         Pen:tag(name: string) -> Pen
            Tag the most recently drawn segment with a name.

            Tags are unique: re-using a name raises an error. Use `:get(name)` to
            retrieve the curve later.

         Pen:turn(delta_deg: number, dist: number) -> Pen
            Turn relative to the current heading, then move forward.

         Pen:west(d: number) -> Pen


   jnl.geo2d.types.Curve2D
      Constructors
         jnl.geo2d.curve.between(p0: Point2D, p1: Point2D) -> Curve2D
         jnl.geo2d.curve.circle(centre: Point2D, radius: number, opts?: {
         angle0:number?, clockwise:boolean? }) -> Curve2D
         jnl.geo2d.curve.circular_arc(centre: Point2D, radius: number, theta0: number,
         theta1: number) -> Curve2D
         jnl.geo2d.curve.closed_polyline(points: Point2D[], eps: number?) -> Curve2D
         jnl.geo2d.curve.join(curves: (Curve2D|nil)[]) -> Curve2D
         jnl.geo2d.curve.map(curve: Curve2D, fn: fun(x:number, y:number): number,
         number, opts?: { n:integer?, distribution:Dist1D?, mode:Curve2DSampleMode? })
         -> Curve2D
         jnl.geo2d.curve.rectangle(x0: number, y0: number, x1: number, y1: number) ->
         Curve2D
         jnl.geo2d.curve.rotate(curve: Curve2D, angle: number, centre: Point2D?, opts?:
         table) -> Curve2D
         jnl.geo2d.curve.scale(curve: Curve2D, sx: number, sy: number?, opts?: table) ->
         Curve2D
         jnl.geo2d.curve.through(points: Point2D[]) -> Curve2D
         jnl.geo2d.curve.translate(curve: Curve2D, dx: number, dy: number, opts?: table)
         -> Curve2D
      Methods

         Curve2D:clone() -> Curve2D
            Return an independent deep clone.

         Curve2D:eval(t: number) -> Point2D
            Evaluate using the curve's native parameterisation.
            t                   Normalised parameter in [0, 1].

         Curve2D:eval_arclen(s: number) -> Point2D
            Evaluate using normalised arc length.
            s                   Normalised arc length in [0, 1].

         Curve2D:finish() -> Point2D
            Return the final point in the current orientation.

         Curve2D:kind() -> Curve2DKind
            Return the curve kind.

         Curve2D:length() -> number
            Return the total curve length.

         Curve2D:reverse_inplace() -> self
            Reverse this curve in place and return it.

         Curve2D:reversed() -> Curve2D
            Return an independent curve with reversed orientation.

         Curve2D:sample(n: integer, distribution: Dist1D?, mode: Curve2DSampleMode?) ->
         Point2D[]
            Sample points from the curve.

         Curve2D:start() -> Point2D
            Return the first point in the current orientation.

         Curve2D:tangent_end() -> number, number
            Unit tangent vector at the end of the curve.
            return 1            tx
            return 2            ty

         Curve2D:tangent_start() -> number, number
            Unit tangent vector at the start of the curve.
            return 1            tx
            return 2            ty


   jnl.geo2d.types.Curve2DSampleMode [alias]
      = "arclen"|"param"

   jnl.geo2d.types.Dist1D
      Methods

         Dist1D:eval(i: integer, n: integer) -> number
            Evaluate the normalised coordinate for zero-based point index i out of n
            points.

         Dist1D:kind() -> Dist1DKind
            Return the distribution kind.


   jnl.geo2d.types.Domain2D
      _reg: MarkerRegistry?         Marker registry attached by `domain.from_pen`.
      Constructors
         jnl.geo2d.domain.from_pen(p: Pen, opts: Domain2DOpts?) -> Domain2D,
         MarkerRegistry
      Methods

         Domain2D:add_hole(name: string?, boundary: Curve2D, seed: Point2D) -> self
            Add a closed interior hole. `seed` must be a point strictly inside the hole
            (used to suppress interior cells).
            boundary            Must be a closed curve.
            seed                Interior point.

         Domain2D:add_patch(name: string, curve: Curve2D) -> self
            Add a named boundary patch (a sub-curve of the outer boundary).

         Domain2D:add_region(name: string, seed: Point2D, max_area: number?) -> self
            Add a region seed for cell-region labelling and per-region area constraints.
            max_area            Area constraint; `<= 0` means unconstrained.

         Domain2D:bbox() -> BoundingBox
            Return the bounding box of the outer boundary (approximate).

         Domain2D:check() -> true?, string?
            Validate the domain. Returns `true` on success, or `nil, message` on
            failure.
            return 2            err

         Domain2D:contains(point: Point2D, sample_n: integer?) -> boolean
            True if `point` is strictly inside the outer boundary and outside all holes.
            sample_n            Sample resolution (default 128).

         Domain2D:curve_intersects_boundary(curve: Curve2D, sample_n: integer?) ->
         boolean
            True if any segment of `curve` intersects any domain boundary.
            sample_n            Sample resolution (default 128).

         Domain2D:holes_intersect(i: integer, j: integer, sample_n: integer?) -> boolean
            True if holes `i` and `j` have intersecting boundaries.
            i                   1-based hole index.
            j                   1-based hole index.
            sample_n            Default 128.

         Domain2D:n_holes() -> integer

         Domain2D:n_patches() -> integer

         Domain2D:n_regions() -> integer

         Domain2D:outer_self_intersects(sample_n: integer?) -> boolean
            True if the outer boundary self-intersects at the given resolution.
            sample_n            Default 128.

         Domain2D:sample_all(n: integer) -> Domain2DSampleResult[]
            Sample all boundaries.

            Result layout: `[1]` outer boundary, `[2..n_holes+1]` holes, `[n_holes+2..]`
            patches.

         Domain2D:sample_hole(i: integer, n: integer) -> Point2D[]
            Sample hole `i` (1-based) at `n` arc-length-distributed points.
            i                   1-based hole index.

         Domain2D:sample_outer(n: integer) -> Point2D[]
            Sample the outer boundary at `n` arc-length-distributed points.

         Domain2D:set_default_marker(marker: integer) -> self
            Set the marker applied to unpatched outer boundary edges.


   jnl.geo2d.types.PSLG
      Constructors
         jnl.geo2d.curve.discretise(curve: Curve2D, marker: integer?, opts?: table) ->
         PSLG
         jnl.mesh2d.tri.pslg_from_domain(domain: Domain2D, opts?: { n:integer? }) ->
         PSLG?, string?
      Methods

         PSLG:bbox() -> number, number, number, number
            Return the bounding box as four numbers.
            return 1            min_x
            return 2            min_y
            return 3            max_x
            return 4            max_y

         PSLG:edge_add(p: integer, q: integer, marker: integer?) -> integer
            Add a constrained edge between two node indices.

         PSLG:edge_count() -> integer
            Return the current edge count.

         PSLG:hole_add(x: number, y: number) -> integer
            Add a hole seed point.

         PSLG:node_add(x: number, y: number, marker: integer?) -> integer
            Add a node and return its index.

         PSLG:node_count() -> integer
            Return the current node count.

         PSLG:node_find_nearest(x: number, y: number) -> integer?
            Find the nearest node to a point, or nil if empty.

         PSLG:node_find_or_add(x: number, y: number, marker: integer?, eps: number?) ->
         integer
            Find a node within eps of the point, or add it.

         PSLG:node_get(idx: integer) -> number?, number?
            Retrieve a node's coordinates by index, or nil if out of bounds.

         PSLG:region_add(x: number, y: number, marker: integer?, max_area: number?) ->
         integer
            Add a region seed point with optional area constraint.


   jnl.mesh2d.block.BlockBuilder
      Constructors
         jnl.mesh2d.block.block(ni: integer, nj: integer) -> BlockBuilder
      Methods

         BlockBuilder:build() -> Mesh2D?, string?
            Lower the block to a Mesh2D.
            return 1            mesh
            return 2            err

         BlockBuilder:east(c: Curve2D, opts?: { marker:integer?, dist:Dist1D? }) ->
         BlockBuilder

         BlockBuilder:edge(edge: integer, c: Curve2D, opts?: { marker:integer?,
         dist:Dist1D? }) -> BlockBuilder
            Set an edge by direction constant.
            edge                Direction constant (E.S / E.E / E.N / E.W).

         BlockBuilder:from_pen(p: Pen, mapping: table<string, string>, markers:
         table<string, integer>?) -> BlockBuilder
            Populate edges from a Pen's tagged segments.

         BlockBuilder:north(c: Curve2D, opts?: { marker:integer?, dist:Dist1D? }) ->
         BlockBuilder

         BlockBuilder:smooth(opts?: { max_iter:integer?, omega:number?, tol:number? })
         -> BlockBuilder

         BlockBuilder:south(c: Curve2D, opts?: { marker:integer?, dist:Dist1D? }) ->
         BlockBuilder
            Set the south (j = 0) edge.

         BlockBuilder:tfi() -> BlockBuilder

         BlockBuilder:to_domain() -> Domain2D?, string?

         BlockBuilder:west(c: Curve2D, opts?: { marker:integer?, dist:Dist1D? }) ->
         BlockBuilder


   jnl.mesh2d.block.GridBuilder
      blocks: GridBlockHandle[]     
      joins: GridJoin[]             
      Constructors
         jnl.mesh2d.block.grid() -> GridBuilder
      Methods

         GridBuilder:block(ni: integer, nj: integer, opts?: { tfi:boolean?,
         smooth:table? }) -> GridBlockHandle
            Add a block to the grid and return a handle for edge assignment.

            tfi and smooth may be set immediately as shorthand:

            local b = g:block(33, 33, { tfi = true, smooth = { max_iter = 100 } })

         GridBuilder:build() -> Mesh2D?, string?
            Build the grid into a single Mesh2D.
            return 1            mesh
            return 2            err

         GridBuilder:join(src_blk: GridBlockHandle, src_edge: integer, dst_blk:
         GridBlockHandle, dst_edge: integer, reversed: boolean?) -> GridBuilder
            Declare a topology join between two block edges.

            src_blk.src_edge must be assigned by the caller. dst_blk.dst_edge must NOT
            be assigned; build() populates it via copy_edge in declaration order before
            running TFI.

            Multi-hop chains (A -> B -> C) work provided joins are declared in
            propagation order.
            return 1            self

         GridBuilder:join_ring(blocks: GridBlockHandle[], out_edge: integer, in_edge:
         integer, reversed: boolean?) -> GridBuilder
            Declare cyclic joins between a sequence of blocks.

            Joins blocks[1].out_edge -> blocks[2].in_edge, ..., blocks[n].out_edge ->
            blocks[1].in_edge.

            Used for O-meshes and any topology that wraps around a full loop.
            out_edge            Source edge on each block (e.g. E.E).
            in_edge             Destination edge on each block (e.g. E.W).
            return 1            self

         GridBuilder:to_domain() -> Domain2D?, string?
            return 1            domain
            return 2            err


   jnl.mesh2d.tri.TriSpecBuilder
      opts: table                   
      spec: table                   
      Constructors
         jnl.mesh2d.tri.spec() -> TriSpecBuilder
      Methods

         TriSpecBuilder:baffle(name: string, marker: integer) -> TriSpecBuilder
            return 1            self

         TriSpecBuilder:cell_count(pslg: PSLG, n: integer) -> TriSpecBuilder
            Derive the global max area from a target cell count.
            return 1            self

         TriSpecBuilder:conforming(enabled: boolean?) -> TriSpecBuilder
            return 1            self

         TriSpecBuilder:from_domain_reg(registry: MarkerRegistry) -> TriSpecBuilder
            Populate patch, baffle, and region tags from a MarkerRegistry.

            The registry is produced by domain.from_pen() and carries the name→marker
            mapping built during pen tracing.
            return 1            self

         TriSpecBuilder:max_area(area: number) -> TriSpecBuilder
            area                Global maximum triangle area.
            return 1            self

         TriSpecBuilder:min_angle(deg: number) -> TriSpecBuilder
            deg                 Minimum interior angle in degrees.
            return 1            self

         TriSpecBuilder:patch(name: string, marker: integer) -> TriSpecBuilder
            Add a named patch tag directly.
            return 1            self

         TriSpecBuilder:quiet(enabled: boolean?) -> TriSpecBuilder
            return 1            self

         TriSpecBuilder:region(name: string, marker: integer) -> TriSpecBuilder
            return 1            self

         TriSpecBuilder:region_areas(enabled: boolean?) -> TriSpecBuilder
            enabled             Defaults to true.
            return 1            self

         TriSpecBuilder:resolution(pslg: PSLG, res: number) -> TriSpecBuilder
            Derive the global max area from a target mean edge length.
            return 1            self

         TriSpecBuilder:triangulate(pslg: PSLG) -> Mesh2D?, string?
            Triangulate a PSLG and return a Mesh2D.
            return 1            mesh
            return 2            err


   jnl.mesh2d.types.Mesh2D
      A built 2D finite-volume polymesh.
      Constructors
         jnl.mesh2d.cartesian.build(width: number, height: number, nx: integer, ny:
         integer) -> Mesh2D?, string?
         jnl.mesh2d.tri.from_domain(domain: Domain2D, spec: TriSpecBuilder, opts?: {
         n:integer? }) -> Mesh2D?, string?
      Methods

         Mesh2D:cell_centre(i: integer) -> number, number
            Cell centre coordinates, 1-based.
            return 1            x
            return 2            y

         Mesh2D:cell_cx_vec() -> VecUD
            Borrowed slice of real-cell x-coordinates. The mesh must remain alive.

         Mesh2D:cell_cy_vec() -> VecUD
            Borrowed slice of real-cell y-coordinates. The mesh must remain alive.

         Mesh2D:cell_vol(i: integer) -> number
            Cell area for cell i, 1-based.

         Mesh2D:cell_vol_vec() -> VecUD
            Borrowed slice of real-cell volumes. The mesh must remain alive.

         Mesh2D:face_area0(f: integer) -> number
            f                   0-based face index.

         Mesh2D:face_centre(i: integer) -> number, number
            Face centre coordinates, 1-based.
            return 1            x
            return 2            y

         Mesh2D:face_centre0(f: integer) -> number, number
            f                   0-based face index.
            return 1            x
            return 2            y

         Mesh2D:face_neighbour0(f: integer) -> integer
            Neighbour cell index for face f, 0-based.

            For boundary and baffle faces the neighbour is a ghost cell; no
            negative-marker encoding is used.
            f                   0-based face index.

         Mesh2D:face_normal(i: integer) -> number, number
            Face outward unit normal, 1-based.
            return 1            nx
            return 2            ny

         Mesh2D:face_normal0(f: integer) -> number, number
            f                   0-based face index.
            return 1            nx
            return 2            ny

         Mesh2D:face_owner0(f: integer) -> integer
            Owner cell index for face f, 0-based.
            f                   0-based face index.

         Mesh2D:mean_cell_size() -> number
            Square root of mean cell area.

         Mesh2D:n_baffle_faces() -> integer

         Mesh2D:n_boundary_faces() -> integer

         Mesh2D:n_cells() -> integer
            Number of real (conservation-volume) cells.

         Mesh2D:n_faces() -> integer

         Mesh2D:n_ghost_cells() -> integer

         Mesh2D:n_internal_faces() -> integer

         Mesh2D:n_patches() -> integer

         Mesh2D:n_real_cells() -> integer

         Mesh2D:n_total_cells() -> integer
            Total cell count including ghost cells.

         Mesh2D:patch_by_name(name: string) -> MeshPatch?

         Mesh2D:patches() -> MeshPatch[]


   jnl.nabla.node.Node
      Expression graph node for the Nabla symbolic system. All constructor functions
      return a Node; arithmetic operators are overloaded. Nodes are immutable once
      constructed — all operations return new nodes.
      kind: string                  Node kind tag.
      rank: integer                 Tensor rank: 0 = scalar, 1 = vector, 2 = tensor.
      name: string?                 Declared symbol name, if any.
      a: Node?                      First child.
      b: Node?                      Second child.
      x: Node                       x-component (rank >= 1 nodes only; via __index).
      y: Node                       y-component (rank >= 1 nodes only; via __index).
      z: Node                       z-component (rank >= 1 nodes only; via __index).
      Methods

         Node:T() -> Node
            Alias for transpose.

         Node:add(...: Node|number) -> Node
            Add one or more nodes to this node. Rank must match across all operands.

         Node:cross(b: Node) -> Node
            Cross product of two rank-1 vectors, producing a rank-1 vector.

         Node:curl(...) -> Node
            Curl of a vector field, producing a vector (or pseudoscalar in 2D).

         Node:ddot(b: Node) -> Node
            Double contraction of two rank-2 tensors, producing a scalar.

         Node:ddt(...) -> Node
            Time derivative operator ∂/∂t applied to this field.

         Node:dev() -> Node
            Deviatoric part of a rank-2 tensor: A - (tr(A)/3) I.

         Node:div(...) -> Node
            Divergence of a vector field, producing a scalar.

         Node:divide(...: Node|number) -> Node
            Divide this node by one or more nodes in left-to-right order. Both quotient
            and divisor must be rank-0 (scalar).

         Node:dot(b: Node) -> Node
            Inner (dot) product of two vectors, producing a scalar.

         Node:equals(rhs: Node) -> Equation
            Construct an equation asserting this node equals rhs.

         Node:exponentiate(pow: Node|number) -> Node
            Raise this rank-0 node to a scalar power.

         Node:flatten(kind: string) -> Node[]
            Flatten all child nodes of the given kind into a flat list. Useful for
            printing and analysis passes.

         Node:grad(...) -> Node
            Gradient of a scalar field, producing a vector; or gradient of a vector,
            producing a tensor.

         Node:inv() -> Node
            Inverse of a rank-2 tensor.

         Node:is_anon_const()

         Node:is_leaf() -> boolean
            Return true if this is a leaf node (symbol, constant, or cvec).

         Node:is_minus_one()

         Node:is_one()

         Node:is_rank(n: integer) -> boolean
            Return true if this node's tensor rank equals n.

         Node:is_scalar()

         Node:is_tensor()

         Node:is_vector()

         Node:is_zero()

         Node:lap(...) -> Node
            Alias for laplacian.

         Node:laplacian(...) -> Node
            Laplacian operator, optionally with a diffusivity coefficient.

         Node:mag() -> Node
            Euclidean magnitude of a vector, producing a scalar.

         Node:mul(...: Node|number) -> Node
            Alias for multiply.

         Node:multiply(...: Node|number) -> Node
            Multiply this node by one or more nodes. Rank dispatch: scalar*scalar->mul,
            scalar*vector->scale, vector*vector->dot, tensor*vector->matvec,
            tensor*tensor->matmul.

         Node:neg() -> Node
            Negate this node: returns -self.

         Node:negate() -> Node
            Negate this node: returns -self.

         Node:outer(b: Node) -> Node
            Outer (tensor) product of two vectors, producing a rank-2 tensor.

         Node:pow(pow: Node|number) -> Node
            Alias for exponentiate.

         Node:scratch_depth() -> integer
            Return the number of scratch buffers needed to evaluate this node, using the
            Sethi-Ullman register allocation algorithm.

         Node:simplify() -> Node
            Return a simplified form of this expression tree.

         Node:skew() -> Node
            Skew-symmetric (anti-symmetric) part of a rank-2 tensor: (A - A^T) / 2.

         Node:sub(...: Node|number) -> Node
            Alias for subtract.

         Node:subtract(...: Node|number) -> Node
            Subtract one or more nodes from this node in left-to-right order. Rank must
            match across all operands.

         Node:symm() -> Node
            Symmetric part of a rank-2 tensor: (A + A^T) / 2.

         Node:to_number() -> number
            Return the numeric value of a constant node, errors if different type

         Node:trace() -> Node
            Trace of a rank-2 tensor, producing a scalar.

         Node:transpose() -> Node
            Transpose of a rank-2 tensor.


   jnl.nabla.registry.Registry
      Declare fields, constants, governing equations, and derived expressions for a
      symbolic physics model.

      A registry stores named symbolic fields in declaration order. Field declarations
      return injected `Node` instances with chainable methods such as `governed_by`,
      `defined_as`, `prescribed`, and `initial`.
      label: string?                Human-readable registry label.
      entries: table<string, RegistryEntry>
         Field entries by name.
      order: string[]               Declaration order.
      Constructors
         jnl.fvm.preset.reg.ns(opts?: RegOpts) -> Registry
         jnl.fvm.preset.reg.stokes(opts?: RegOpts) -> Registry
      Methods

         Registry:const(name: string, value: number) -> Node
            Declare a named scalar constant.
            name                Constant name.
            value               Constant value.
            return 1            node

         Registry:cvec(name: string, ...: number) -> Node
            Declare a named constant vector.
            name                Constant vector name.
            ...                 Vector components.
            return 1            node

         Registry:dep_listing() -> string
            Return a multi-line dependency listing.
            return 1            text

         Registry:deps_of(name: string) -> table
            Return dependency sets for a field.
            name                Field name.
            return 1            deps

         Registry:diagnostics() -> string[]
            Return names of diagnostic fields defined by expressions.
            return 1            names

         Registry:each(fn: fun(name: string, entry: RegistryEntry))
            Iterate over entries in declaration order.

         Registry:entry(name: string) -> RegistryEntry?
            Return a registry entry by name, or nil if absent.
            name                Field name.
            return 1            entry

         Registry:expect(name: string) -> RegistryEntry
            Return a registry entry by name, raising an error if absent.
            name                Field name.
            return 1            entry

         Registry:get(name: string) -> RegistryField
            Return an injected field node by name.
            name                Field name.
            return 1            field

         Registry:listing() -> string
            Return a multi-line listing of constants, diagnostics, prescribed fields,
            and prognostics.
            return 1            text

         Registry:new(label?: string) -> Registry
            Create a new registry.
            label               Human-readable label.
            return 1            registry

         Registry:prescribed_fields() -> string[]
            Return names of externally prescribed fields.
            return 1            names

         Registry:prognostics() -> string[]
            Return names of fields solved from governing equations.
            return 1            names

         Registry:scalar(name: string) -> RegistryField
            Declare a scalar field.
            name                Field name.
            return 1            field

         Registry:set_clip(name: string, lo: number, hi: number)
            Set clipping limits for a declared field.
            name                Field name.
            lo                  Lower bound.
            hi                  Upper bound.

         Registry:set_initial(name: string, value: number)
            Set the initial value for a declared field.
            name                Field name.
            value               Initial value.

         Registry:tensor(name: string, rank?: integer) -> RegistryField
            Declare a tensor field.
            name                Field name.
            rank                Tensor rank; defaults to 2.
            return 1            field

         Registry:validate()
            Validate declarations, dependencies, and equation ranks.

         Registry:vector(name: string) -> RegistryField
            Declare a vector field.
            name                Field name.
            return 1            field


   jnl.repl.Repl
      A configurable JNL Fennel REPL instance.
      registry: table<string, jnl.repl.RegistryEntry>
      commands: table<string, jnl.repl.Command>
      help_width: integer           
      doc_index: DocIndex?          
      usage_spec: ReplUsageSpec?    
      globals_at_start: table<string, boolean>
      fennel: table?                
      quit: boolean                 
      started: boolean              
      running: boolean              
      Constructors
         jnl.repl.default() -> jnl.repl.Repl
         jnl.repl.new(opts?: table) -> jnl.repl.Repl
      Methods

         Repl:command(name: string, fn: fun(repl: jnl.repl.Repl, arg: string), usage?:
         string, doc?: string)
            Register a custom comma command.
            name                Command name without the comma.
            usage               Displayed command usage.
            doc                 Help text.

         Repl:pp(value: any, opts?: table) -> any
            Pretty-print a Lua or Fennel value and return it unchanged.
            value               Value to print.
            opts                Fennel view options.
            return 1            value

         Repl:print_usage()
            Print registered study-specific usage text.

         Repl:register(name: string, value: any, doc?: ReplDocSpec) -> any
            Expose a value as a global and register it with the help system.

            When `doc` is omitted, the documentation index is searched for a uniquely
            matching symbol, type, or module. A string is literal help text. A table may
            contain `from` for explicit lookup or `doc` for literal text. Pass `false`
            to suppress lookup.
            name                User-facing global name.
            value               Value to expose.
            doc                 Documentation source.
            return 1            value

         Repl:run()
            Start the Fennel REPL loop.

         Repl:special(name: string, value: any, label?: string|false) -> any
            Store a value in a named REPL special such as `*last-run*`.
            name                Special name surrounded by asterisks.
            value               Value to store.
            label               Optional confirmation label; false suppresses output.
            return 1            value

         Repl:stop()
            Request that this REPL loop stops.

         Repl:usage(spec: ReplUsageSpec)
            Register study-specific usage text or a usage provider.
            spec                Usage source.

         Repl:usage_string() -> string
            Return registered study-specific usage text.
            return 1            text


   jnl.repl.core.ReplDocSpec [alias]
      string                    
      false                     
      { doc:string?, from:string?, lookup:boolean? }

   jnl.repl.core.ReplUsageSpec [alias]
      string                    
      fun(repl: jnl.repl.Repl): string
      table                     

   jnl.repl.printer.Printer
      A buffered or callback-backed terminal text printer.
      width: integer                Maximum output width.
      out: fun(text: string)        Output callback.
      buffer: string[]              Buffered chunks used by `string`.
      Constructors
         jnl.repl.printer.new(opts?: table) -> Printer
      Methods

         Printer:blank()
            Emit one blank line.

         Printer:bullet(text: any, opts?: table)
            Emit a Markdown-style bullet.
            text                Bullet text.
            opts                Formatting options.

         Printer:columns(left: any, right: any, opts?: table)
            Emit a responsive two-column row.

            The row is rendered inline when enough room remains for the right column.
            Otherwise the left and right values are stacked.
            left                Left-hand label.
            right               Right-hand description.
            opts                Column layout options.

         Printer:header(text: any, level?: integer)
            Emit a Markdown-style heading.
            text                Heading text.
            level               Heading level from 1 to 6.

         Printer:item(name: any, fields: table[], opts?: table)
            Emit a named item followed by labelled fields.
            name                Item name.
            fields              Fields represented as `{ label, text }`.
            opts                Item layout options.

         Printer:kv(key: any, value: any, opts?: table)
            Emit a key-value line.
            key                 Key or label.
            value               Value text.
            opts                Formatting options.

         Printer:line(text?: any)
            Emit one line.
            text                Line content.

         Printer:rule(opts?: table)
            Emit a Markdown horizontal rule.
            opts                Formatting options.

         Printer:string() -> string
            Return all output accumulated by the default buffered sink.
            return 1            text

         Printer:wrap(first_indent?: string, rest_indent?: string, text?: any)
            Emit wrapped text with separate first-line and continuation indents.
            first_indent        First-line indentation or prefix.
            rest_indent         Continuation indentation.
            text                Text to wrap.



