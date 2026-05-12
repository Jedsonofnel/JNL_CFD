-- fvm/init.lua - re-exports from other fvm files
-- <jed@nelson.ac> // 2026-05-12

local FVM = {}

local eq = require("fvm.eq")
FVM.Op = eq.Op
FVM.Expr = eq.Expr
FVM.eq = eq.Eq -- lower case as it's a function NOT a module

local case = require("fvm.case")
FVM.Case = case

return FVM
