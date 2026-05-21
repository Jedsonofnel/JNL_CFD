-- repl.lua - REPL for interacting with the JNL suite
-- <jed@nelson.ac> // 2026-05-21

local geo2d = require("jnl.geo2d")

print("JNLCFD REPL")
print("Testing C integration...")

geo2d.geo2d_test()

--
-- Post script analysis
--

if _script then
	local stdlib = {
		_G = 1,
		_VERSION = 1,
		assert = 1,
		collectgarbage = 1,
		dofile = 1,
		error = 1,
		getmetatable = 1,
		ipairs = 1,
		load = 1,
		loadfile = 1,
		next = 1,
		pairs = 1,
		pcall = 1,
		print = 1,
		rawequal = 1,
		rawget = 1,
		rawlen = 1,
		rawset = 1,
		require = 1,
		select = 1,
		setmetatable = 1,
		tonumber = 1,
		tostring = 1,
		type = 1,
		warn = 1,
		xpcall = 1,
		coroutine = 1,
		debug = 1,
		io = 1,
		math = 1,
		os = 1,
		package = 1,
		string = 1,
		table = 1,
		utf8 = 1,
		_script = 1,
	}

	local user_globals = {}
	for k, _ in pairs(_G) do
		if not stdlib[k] then
			table.insert(user_globals, k)
		end
	end

	table.sort(user_globals)

	print(string.format("ran %s", _script))
	if #user_globals > 0 then
		print("globals: " .. table.concat(user_globals, ", "))
	else
		print("note: script set no globals — if you want to explore state,")
		print("      assign to globals rather than locals in your script")
	end
end

--
-- simple REPL loop
--

io.write("> ")
for line in io.lines() do
	local fn, err = load("return " .. line, "repl", "t")
	if not fn then
		fn, err = load(line, "repl", "t")
	end
	if fn then
		local ok, res = pcall(fn)
		if ok and res ~= nil then print(res) end
	else
		print("error: " .. err)
	end
	io.write("> ")
end
