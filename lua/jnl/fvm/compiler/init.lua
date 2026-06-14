-- jnl/fvm/compiler/init.lua - Public FVM compiler interface
-- <jed@nelson.ac> // 2026-06-13

local Expand = require("jnl.fvm.compiler.expand")
local Elab   = require("jnl.fvm.compiler.elab")
local Lower  = require("jnl.fvm.compiler.lower")

--- FVM compilation pipeline.
---
--- The three phases are deliberately exposed so host code (case builders,
--- tests, REPL inspection) can run them individually.  Use compile() when
--- you want the full pipeline in one call.
local M      = {}

--- Expand an algorithm into an abstract three-phase schedule.
---
--- Populates alg.pre, alg.main, and alg.post with abstract instructions
--- (fill, evaluate, solve, correct, clip, zero).  Abstract ops are not yet
--- expanded to concrete FVM assembly.
---@param alg Algorithm
---@param reg Registry
function M.expand(alg, reg)
	Expand.expand(alg, reg)
end

--- Discover intermediate fields and build the resource manifest.
---
--- Must run after expand().  Sets alg.elaborated (intermediate field
--- registry and face-flux map) and alg.manifest (cell, face, system, and
--- scratch allocations).
---@param alg Algorithm
---@param reg Registry
function M.elaborate(alg, reg)
	Elab.elaborate(alg, reg)
end

--- Lower the abstract schedule to concrete FVM assembly instructions.
---
--- Must run after elaborate().  Replaces abstract solve/evaluate/correct ops
--- in alg.pre, alg.main, and alg.post with concrete instruction sequences.
---@param alg Algorithm
---@param reg Registry
function M.lower(alg, reg)
	Lower.lower(alg, reg)
end

--- Lower a single registry entry's equation to a concrete instruction list.
---
--- Useful for inspecting what assembly a specific field equation produces
--- without running the full algorithm pipeline.  The alg passed here must
--- already have alg.elaborated set (i.e. elaborate() must have run).
---
--- Returns the instruction list and a small info table so callers can make
--- assertions without reimplementing instruction walks.
---@param field string    Field name being solved.
---@param entry table     Registry entry (from reg:entry(field)).
---@param elab  table     Elaboration result (alg.elaborated).
---@return Inst[]         instructions
---@return table          info  { has_div_cells, has_ghost_fills, n_instructions }
function M.lower_equation(field, entry, elab)
	return Lower.lower_equation(field, entry, elab)
end

--- Run the full compilation pipeline in order.
---@param alg Algorithm
---@param reg Registry
function M.compile(alg, reg, opts)
	opts = opts or {}
	Expand.expand(alg, reg)
	Elab.elaborate(alg, reg)
	Lower.lower(alg, reg, opts.ndims or 2)
end

return M
