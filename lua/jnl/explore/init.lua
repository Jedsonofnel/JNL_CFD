-- jnl/explore/init.lua - Domain-unaware exploration helpers
-- <jed@nelson.ac> // 2026-05-27

local M = {}

M._doc = "Domain-unaware statistics, uncertainty and exploration helpers."

M.stat = require("jnl.explore.stat")
M.uq = require("jnl.explore.uq")

return M
