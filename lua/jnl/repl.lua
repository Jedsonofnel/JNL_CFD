-- repl.lua - REPL for interacting with the JNL suite
-- <jed@nelson.ac> // 2026-05-21

local geo2d = require("jnl.geo2d")

print("JNLCFD REPL")
print("Testing C integration...")

geo2d.geo2d_test()

-- simple REPL loop

io.write("> ")
for line in io.lines() do
	local fn, err = load(line, "repl", "t")
	if fn then
		local ok, res = pcall(fn)
		if ok and res ~= nil then print(res) end
	else
		print("error: " .. err)
	end
	io.write("> ")
end
