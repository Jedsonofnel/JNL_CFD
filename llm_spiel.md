
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

   (no module description)

   Functions

      jnl.fvm.algorithm.default_config()

      jnl.fvm.algorithm.new(label)


## jnl.fvm.bc

   (no module description)

   Functions

      jnl.fvm.bc.dirichlet(value)

      jnl.fvm.bc.dirichlet_v(ux, uy)

      jnl.fvm.bc.fixed(value)

      jnl.fvm.bc.free_slip()

      jnl.fvm.bc.inlet(ux, uy)

      jnl.fvm.bc.moving_wall(ux, uy)

      jnl.fvm.bc.neumann(grad_n)

      jnl.fvm.bc.neumann_v(ux_gn, uy_gn)

      jnl.fvm.bc.new_set()

      jnl.fvm.bc.no_slip()

      jnl.fvm.bc.nograd()

      jnl.fvm.bc.nt(nkind, nval, tkind, tval)

      jnl.fvm.bc.outlet()

      jnl.fvm.bc.pressure_outlet(value)

      jnl.fvm.bc.robin(a, b, c)


## jnl.fvm.canned

   (no module description)

   Functions

      jnl.fvm.canned.alg_piso(opts)

      jnl.fvm.canned.alg_simple(opts)

      jnl.fvm.canned.alg_simpler(opts)

      jnl.fvm.canned.reg_laminar_ns(props)

      jnl.fvm.canned.reg_passive_scalar(name, props)

      jnl.fvm.canned.reg_stokes(props)


## jnl.fvm.case

   (no module description)

   Functions

      jnl.fvm.case.new(reg, alg, mesh, bcs)


## jnl.fvm.compiler

   (no module description)

   Functions

      jnl.fvm.compiler.compile(alg, reg)


## jnl.fvm.instruction

   (no module description)

   Functions

      jnl.fvm.instruction.apply_correction(field, node)
         evaluates correction node expression into delta and does field:axpy(1, delta)

      jnl.fvm.instruction.clip(field, lo, hi)

      jnl.fvm.instruction.comment(text: string?)

      jnl.fvm.instruction.correct(field)

      jnl.fvm.instruction.ddt_f(field: string, rho: string, expr: Node?)
         rho                 Name of rho field
         expr                Optional rho-expr for display

      jnl.fvm.instruction.ddt_k(field: string, rho: number, expr: Node?)
         expr                Optional rho-expr for display

      jnl.fvm.instruction.diag_snapshot(field, out)

      jnl.fvm.instruction.div_dc(field: string, flux: string, grad_x: string, grad_y:
      string)
         Explicit deferred correction RHS contribution. runner no-ops if alg:cfg(field,
         "div") == "uds"|"cds"

      jnl.fvm.instruction.div_f(field: string, flux: string, coeff: string, expr: Node?)
         Implicit UDS/CDS convection assembly with named field coefficient.

      jnl.fvm.instruction.div_k(field: string, flux: string, coeff: number)
         Implicit UDS/CDS convection assembly with constant coefficient (rho)

      jnl.fvm.instruction.divergence(face_normal_field, out)

      jnl.fvm.instruction.divergence_c(field, ux, uy, integrated)

      jnl.fvm.instruction.eval_coeff(node)

      jnl.fvm.instruction.eval_expr(field, node)

      jnl.fvm.instruction.evaluate(field: string, implicit: boolean?)

      jnl.fvm.instruction.face_interp(field, out)

      jnl.fvm.instruction.face_normal(ux_face, uy_face, out)

      jnl.fvm.instruction.face_normal_c(ux, uy, out)

      jnl.fvm.instruction.fill(field: string, value: number)

      jnl.fvm.instruction.grad(field, out_x, out_y)

      jnl.fvm.instruction.lap_f(field: string, gamma: string, expr: Node?)

      jnl.fvm.instruction.lap_k(field: string, gamma: number, expr: Node?)
         expr                Optional gamma-expr for display

      jnl.fvm.instruction.lap_nonorth_f(field: string, grad_x: string, grad_y: string,
      coeff: string, expr: Node?)

      jnl.fvm.instruction.lap_nonorth_k(field: string, grad_x: string, grad_y: string,
      coeff: number, expr: Node?)

      jnl.fvm.instruction.new(op, fields)

      jnl.fvm.instruction.pclose_s_d(field: string, patch: string, value: number)

      jnl.fvm.instruction.pclose_s_n(field: string, patch: string, grad_n: number)

      jnl.fvm.instruction.pclose_s_r(field: string, patch: string, a: number, b: number,
      c: number)

      jnl.fvm.instruction.pfill_s_d(field: string, patch: string, value: number)

      jnl.fvm.instruction.pfill_s_n(field: string, patch: string, grad_n: number)

      jnl.fvm.instruction.pfill_s_r(field: string, patch: string, a: number, b: number,
      c: number)

      jnl.fvm.instruction.pfill_v_d(ux: string, uy: string, patch: string, ux_val:
      number, uy_val: number)

      jnl.fvm.instruction.pfill_v_n(ux: string, uy: string, patch: string, ux_gn:
      number, uy_gn: number)

      jnl.fvm.instruction.pfill_v_nt(ux: string, uy: string, patch: string, nkind:
      number, nval: number, tkind: number, tval: number)

      jnl.fvm.instruction.rhie_chow(Ux, Uy, p, grad_px, grad_py, diag_x, diag_y, out)

      jnl.fvm.instruction.solve(field)

      jnl.fvm.instruction.solve_linalg(field)

      jnl.fvm.instruction.sp_f(field: string, coeff: string, volumetric: boolean, expr:
      Node?)

      jnl.fvm.instruction.sp_fs(field: string, scale: number, src: string, volumetric:
      boolean, expr: Node?)
         volumetric          default true

      jnl.fvm.instruction.sp_k(field: string, coeff: number, volumetric: boolean)

      jnl.fvm.instruction.su_f(field: string, coeff: string, volumetric: boolean, expr:
      Node?)

      jnl.fvm.instruction.su_fs(field: string, scale: number, src: string, volumetric:
      boolean, expr: Node?)
         scale               scalar multiplier (negative to subtract)
         src                 name of source cell field
         volumetric          default true

      jnl.fvm.instruction.su_k(field: string, coeff: number, volumetric: boolean)

      jnl.fvm.instruction.sys_reset(field)

      jnl.fvm.instruction.under_relax(field)

      jnl.fvm.instruction.zero(field)


## jnl.fvm.rules

   (no module description)

   Functions

      jnl.fvm.rules.assert_alg_criteria(sage, alg)

      jnl.fvm.rules.change_below(field: string, threshold: number, n_consec: integer?)

      jnl.fvm.rules.nan_guard(field: string?)
         field               default "*"

      jnl.fvm.rules.norm_above(field: string, threshold: number)
         threshold           default 1e10

      jnl.fvm.rules.residual_above(field: string, threshold: number)
         threshold           default 1e10

      jnl.fvm.rules.residual_below(field: string, threshold: number, n_consec: integer?)
         field               field name or "*"
         n_consec            default 1

      jnl.fvm.rules.stopping_ruleset()


## jnl.fvm.runner

   (no module description)

   Functions

      jnl.fvm.runner.new(compiled, field_map, sys_map, mesh, ctx)


## jnl.fvm.sim

   (no module description)

   Functions

      jnl.fvm.sim.new(runner, alg, opts)


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


## jnl.nabla

   (no module description)

   Functions

      jnl.nabla.new_registry(label)

      jnl.nabla.register_accessor(name, spec)


## jnl.nabla.accessor

   (no module description)

   Functions

      jnl.nabla.accessor.get(name)

      jnl.nabla.accessor.register(name: string, spec: table)


## jnl.nabla.equation

   Symbolic equation pairing a left-hand side and right-hand side Node. Constructed via
   Node:equals(rhs) or Equation.new(lhs, rhs).


## jnl.nabla.eval

   (no module description)

   Functions

      jnl.nabla.eval.compile(node: Node, bindings: table<string, userdata|number>)
         Compile a scalar nabla Node against a bindings map. Returns a compiled ud
         object with :eval(pool, n).
         node                rank-0 nabla node

      jnl.nabla.eval.eval(node, bindings, pool, n)

      jnl.nabla.eval.scratch_depth(node)


## jnl.nabla.mangle

   (no module description)

   Functions

      jnl.nabla.mangle.accessor(kind: string, node: Node) -> string
         Mangle a resolved accessor node to a flat binding name.

      jnl.nabla.mangle.field(name: string, axis: string) -> string
         Mangle a resolved field component to a binding name

      jnl.nabla.mangle.grad(name: string, i: string, j: string?) -> string
         Mangle a grad tensor component

      jnl.nabla.mangle.tensor(name: string, axis_i: string, axis_j: string) -> string
         Mangle a rank-2 symbol component


## jnl.nabla.node

   Expression graph node for the Nabla symbolic system. All constructor functions return
   a Node; arithmetic operators are overloaded. Nodes are immutable once constructed —
   all operations return new nodes.


## jnl.nabla.ops

   (no module description)

   Functions

      jnl.nabla.ops.cross(a, b)

      jnl.nabla.ops.curl(...)

      jnl.nabla.ops.ddot(a, b)

      jnl.nabla.ops.ddt(...)

      jnl.nabla.ops.dev(a)

      jnl.nabla.ops.div(...)

      jnl.nabla.ops.dot(a, b)

      jnl.nabla.ops.grad(...)

      jnl.nabla.ops.inv(a)

      jnl.nabla.ops.laplacian(...)

      jnl.nabla.ops.mag(a)

      jnl.nabla.ops.outer(a, b)

      jnl.nabla.ops.pow_dispatch(a, b)

      jnl.nabla.ops.skew(a)

      jnl.nabla.ops.symm(a)

      jnl.nabla.ops.trace(a)

      jnl.nabla.ops.transpose(a)


## jnl.nabla.pretty

   (no module description)

   Functions

      jnl.nabla.pretty(node, parent_prec, is_right)


## jnl.nabla.registry

   (no module description)

   Functions

      jnl.nabla.registry.new(label)


## jnl.nabla.resolve

   (no module description)

   Functions

      jnl.nabla.resolve.install(Node_class, Equation_class)

      jnl.nabla.resolve.resolve(node, ndims)

      jnl.nabla.resolve.resolve_equation(eq, ndims)


## jnl.nabla.simplify

   (no module description)

   Functions

      jnl.nabla.simplify(node)


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

         BlockBuilder:west(c: Curve2D, opts?: { marker:integer?, dist:Dist1D? }) ->
         BlockBuilder


   jnl.mesh2d.block.GridBuilder
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



