---@meta
-- core/types.lua - LuaLS type declarations for jnl
-- <jed@nelson.ac> // 2026-05-22

-- ─────────────────────────────────────────────────────────────────────────────
-- C userdata types
-- ─────────────────────────────────────────────────────────────────────────────

---Compiled C expression tree. Created by Expr:compile(), evaluated via :eval().
---@class ExprUD
---@field set_root     fun(self: ExprUD, node: lightuserdata)
---@field eval         fun(self: ExprUD, pool: ScratchPool, n: integer): VecUD
---@field scratch_depth fun(self: ExprUD): integer

---Scratch buffer pool for expression evaluation.
---Borrowed from ctx:cell_pool() or ctx:face_pool().
---@class ScratchPool

---Vec userdata: a flat f64 array exposed to Lua, backed by C.
---@class VecUD
---@field fill      fun(self: VecUD, val: number)
---@field copy_from fun(self: VecUD, src: VecUD)
---@field norm      fun(self: VecUD): number
---@field max       fun(self: VecUD): number
---@field min       fun(self: VecUD): number
---@field sum       fun(self: VecUD): number
---@field mean      fun(self: VecUD): number
---@field scale     fun(self: VecUD, alpha: number)
---@field axpy      fun(self: VecUD, alpha: number, w: VecUD)
---@field clamp     fun(self: VecUD, lo: number, hi: number)
---@field dot       fun(self: VecUD, other: VecUD): number

-- ─────────────────────────────────────────────────────────────────────────────
-- Expr
-- ─────────────────────────────────────────────────────────────────────────────

---Arithmetic expression node. Constructed via E.sym, E.const, E.add, etc.
---@class Expr
---@field kind           string                   "sym"|"const"|"add"|"sub"|"mul"|"div"|"neg"|"pow"|"addv"|"mulv"|"prime"|"expl"|"prev"|"cell_x"|"cell_y"|"cell_vol"
---@field name           string|nil               Symbol name (kind="sym")
---@field value          number|Expr|nil           Constant value or negation operand
---@field a              Expr|nil                 Left operand of binary op
---@field b              Expr|nil                 Right operand of binary op
---@field base           Expr|nil                 Base of power expression
---@field exp            Expr|nil                 Exponent of power expression
---@field addends        Expr[]|nil               Variadic addition operands
---@field factors        Expr[]|nil               Variadic multiplication operands
---@field field          string|nil               Field name for prime/expl/prev nodes
---@field _dep_name      string|nil               Mangled dependency name for prime/expl/prev
---@field _deps          table<string,true>        Dependency set, populated by make_expr
---@field _ud            ExprUD|nil               Compiled C tree, set by Expr:compile()
---@field _pretty        (fun(): string)|nil       Custom renderer for external nodes
---@field _compile       (fun(ud: ExprUD, build: fun(e: Expr): lightuserdata, bindings: table): lightuserdata)|nil
---@field _walk          (fun(self: Expr, visitor: fun(node: Expr)))|nil
---@field _scratch_depth integer|nil              Scratch depth override for external nodes

-- ─────────────────────────────────────────────────────────────────────────────
-- Term
-- ─────────────────────────────────────────────────────────────────────────────

---A single term in a PDE equation (e.g. laplacian, divergence, source).
---@class Term
---@field kind       string              "ddt"|"lap"|"div"|"su"|"sp"
---@field phi        Expr|nil            Field this term acts on
---@field coeff      Expr|nil            Optional coefficient expression
---@field _backend   string              Backend that created this term ("fvm", ...)
---@field _deps      table<string,true>  Field names this term depends on
---@field _is_linear boolean|nil         Linearity override (nil = use kind default)

-- ─────────────────────────────────────────────────────────────────────────────
-- Eq
-- ─────────────────────────────────────────────────────────────────────────────

---A complete PDE equation: an ordered list of terms that sum to zero.
---@class Eq
---@field terms    Term[]              Ordered list of terms
---@field relax    number|nil          Under-relaxation factor in (0,1], or nil
---@field solver   string              "CG"|"BICGSTAB"
---@field _backend string              Backend that created this equation
---@field _deps    table<string,true>  Union of all term dependencies
