-- lua/jnl/fvm/init.lua - FVM facade: re-exports compiler, case, BC, and operators
-- <jed@nelson.ac> // 2026-05-12

local terms = require("jnl.fvm.terms")

return {
    BC = require("jnl.fvm.bc"),
    chasm = require("jnl.fvm.chasm"),
    physics = require("jnl.fvm.physics"),
    case = require("jnl.fvm.case"),

    terms = terms,
    laplacian = terms.laplacian,
    -- etc
}
