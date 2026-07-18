-- lua/jnl/fvm/init.lua - FVM facade: re-exports compiler, case, BC, and operators
-- <jed@nelson.ac> // 2026-05-12

local terms = require("jnl.fvm.terms")

return {
    physics = require("jnl.fvm.physics"),
    BC = require("jnl.fvm.bc"),
    case = require("jnl.fvm.case"),

    terms = terms,
    laplacian = terms.laplacian,
    -- etc
}
