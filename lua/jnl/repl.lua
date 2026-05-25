-- repl.lua - Configurable REPL for the JNL suite
-- <jed@nelson.ac> // 2026-05-21

local REPL = {}
REPL.__index = REPL

-- Lua stdlib names
local STDLIB = {
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

--
-- Constructor
--

function REPL.new()
	local self = setmetatable({
		_registry = {},
		_commands = {},
	}, REPL)

	self:_register_builtins()
	return self
end

--
-- Public API
--

function REPL:register(name, value, doc)
	self._registry[name] = { value = value, doc = doc or "" }
	_G[name] = value
end

function REPL:command(name, fn, usage, doc)
	self._commands[name] = {
		fn    = fn,
		usage = usage or ("," .. name),
		doc   = doc or "",
	}
end

function REPL:run()
	io.write("JNLCFD |  type ,help for help, ,quit or ctrl-D to exit\n")

	self._globals_at_start = {}
	for k, _ in pairs(_G) do
		self._globals_at_start[k] = true
	end

	local read = readline or function(prompt)
		io.write(prompt)
		io.flush()
		return io.read("l")
	end

	while true do
		local line = read("> ")
		if line == nil then
			io.write("\n")
			break
		end

		line = line:match("^%s*(.-)%s*$")
		if line:sub(1, 1) == "," then
			-- comma command
			local cmd, rest = line:match("^,(%S+)%s*(.*)")
			if cmd then
				self:_dispatch(cmd, rest)
			else
				io.write("error: bare comma — did you mean ,help?\n")
			end
		elseif line ~= "" then
			-- Lua expression/statement
			self:_eval(line)
		end
	end
end

--
-- Built in commands
--

function REPL:_register_builtins()
	self:command("quit", function(_, _)
		io.write("bye\n")
		os.exit(0)
	end, ",quit", "Exit the REPL")

	self:command("help", function(_self, arg)
		arg = arg:match("^%s*(.-)%s*$")
		if arg ~= "" then
			_self:_help_topic(arg)
		else
			_self:_help_overview()
		end
	end, ",help [topic]", "Show help. ,help <name> for a specific registered value or command")

	self:command("globals", function(_self, _)
		local user = {}
		for k, _ in pairs(_G) do
			if not STDLIB[k] and not (_self._globals_at_start and _self._globals_at_start[k]) then
				table.insert(user, k)
			end
		end

		-- also include anything registered before run()
		for k, _ in pairs(_self._registry) do
			user[#user + 1] = k
		end

		-- deduplicate and sort
		local seen = {}
		local dedup = {}
		for _, k in ipairs(user) do
			if not seen[k] then
				seen[k] = true; dedup[#dedup + 1] = k
			end
		end

		table.sort(dedup)
		if #dedup == 0 then
			io.write("no user globals defined\n")
		else
			for _, k in ipairs(dedup) do
				local entry = _self._registry[k]
				local doc   = entry and entry.doc ~= "" and ("  -- " .. entry.doc) or ""
				io.write(string.format("  %-20s %s\n", k, doc))
			end
		end
	end, ",globals", "List user-defined globals (and registered values)")
end

--
-- Internal helpers
--

function REPL:_dispatch(cmd, rest)
	local entry = self._commands[cmd]
	if entry then
		entry.fn(self, rest)
	else
		io.write(string.format(
			"unknown command: ,%s  (type ,help for a list)\n", cmd))
	end
end

function REPL:_eval(line)
	local fn, err = load("return " .. line, "repl", "t")
	if not fn then
		fn, err = load(line, "repl", "t")
	end

	if fn then
		local ok, res = pcall(fn)
		if ok then
			if res ~= nil then
				-- use tostring but handle multiple returns via select
				io.write(tostring(res) .. "\n")
			end
		else
			io.write("error: " .. tostring(res) .. "\n")
		end
	else
		io.write("error: " .. tostring(err) .. "\n")
	end
end

function REPL:_help_overview()
	io.write("\n")
	io.write("  Comma commands\n")
	io.write("  --------------\n")
	-- collect and sort command names
	local names = {}
	for k in pairs(self._commands) do names[#names + 1] = k end
	table.sort(names)
	for _, name in ipairs(names) do
		local c = self._commands[name]
		io.write(string.format("  %-24s %s\n", c.usage, c.doc))
	end
	-- registered values
	local reg_names = {}
	for k in pairs(self._registry) do reg_names[#reg_names + 1] = k end
	table.sort(reg_names)
	if #reg_names > 0 then
		io.write("\n")
		io.write("  Registered globals (,help <name> for detail)\n")
		io.write("  --------------------------------------------\n")
		for _, name in ipairs(reg_names) do
			local e = self._registry[name]
			io.write(string.format("  %-24s %s\n", name, e.doc))
		end
	end
	io.write("\n")
	io.write("  ctrl-D or ,quit to exit\n")
	io.write("\n")
end

function REPL:_help_topic(name)
	-- check registered values first
	local entry = self._registry[name]
	if entry then
		io.write(string.format("\n  %s\n", name))

		if entry.doc ~= "" then
			io.write(string.format("  %s\n", entry.doc))
		end

		io.write(string.format("  type: %s\n\n", type(entry.value)))
		return
	end

	-- check commands
	local cmd = self._commands[name]
	if cmd then
		io.write(string.format("\n  %s\n", cmd.usage))

		if cmd.doc ~= "" then
			io.write(string.format("  %s\n\n", cmd.doc))
		end

		return
	end

	io.write(string.format("no help for '%s'\n", name))
end

--
-- Convenience: post-script summary
--


---Print globals that a script introduced, for the "ran <script>" summary.
function REPL.script_summary(script_path)
	local user_globals = {}

	for k, _ in pairs(_G) do
		if not STDLIB[k] then
			table.insert(user_globals, k)
		end
	end
	table.sort(user_globals)

	print(string.format("ran %s", script_path))
	if #user_globals > 0 then
		print("globals: " .. table.concat(user_globals, ", "))
	else
		print("note: script set no globals")
	end
end

return REPL
