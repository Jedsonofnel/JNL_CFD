-- repl.lua - Configurable REPL for the JNL suite
-- <jed@nelson.ac> // 2026-05-21

local Printer = require("jnl.term_printer")

local REPL = {}
REPL.__index = REPL

REPL._doc = "Configurable Fennel REPL with comma commands and help system"

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
		_help_width = 72,
	}, REPL)

	self:_register_builtins()
	return self
end

-- printer helper
function REPL:_printer(opts)
	opts = opts or {}

	return Printer.new({
		width = opts.width or self._help_width or 72,
		out = opts.out or function(s)
			io.write(s)
		end,
	})
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

--
-- Fennel REPL helpers
--

function REPL:_require_fennel()
	local ok, fennel = pcall(require, "fennel")

	if not ok then
		error("fennel not available; install/require fennel before starting REPL")
	end

	self._fennel = fennel
	return fennel
end

function REPL:_capture_globals_at_start()
	self._globals_at_start = {}

	for k, _ in pairs(_G) do
		self._globals_at_start[k] = true
	end
end

function REPL:_readline(prompt)
	local read = readline or function(p)
		io.write(p)
		io.flush()
		return io.read("l")
	end

	return read(prompt)
end

function REPL:_fennel_prompt(state)
	if state and state["stack-size"] and state["stack-size"] > 0 then
		return ".... "
	end

	return "jnlcfd> "
end

function REPL:_at_top_level(state)
	return not (state and state["stack-size"] and state["stack-size"] > 0)
end

function REPL:_handle_comma_line(line, state)
	if not self:_at_top_level(state) then
		io.write("error: comma commands are only available at top level\n")
		return
	end

	local cmd, rest = line:match("^,(%S+)%s*(.*)")

	if cmd then
		self:_dispatch(cmd, rest or "")
	else
		io.write("error: bare comma — did you mean ,help?\n")
	end
end

function REPL:_read_fennel_chunk(state)
	while true do
		if self._quit then
			return nil
		end

		local line = self:_readline(self:_fennel_prompt(state))

		if line == nil then
			io.write("\n")
			return nil
		end

		line = line:match("^%s*(.-)%s*$")

		if line == "" then
			-- Ignore blank lines.
		elseif line:sub(1, 1) == "," then
			self:_handle_comma_line(line, state)
		else
			return line .. "\n"
		end
	end
end

function REPL:_print_fennel_values(values)
	for _, value in ipairs(values) do
		io.write(value)
		io.write("\n")
	end
end

function REPL:_print_fennel_error(err_type, err, _)
	io.write(string.format("error [%s]: %s\n", err_type, tostring(err)))
end

function REPL:_fennel_view_opts()
	return {
		["line-length"] = self._help_width or 72,
		depth = 8,
	}
end

function REPL:_fennel_repl_options()
	return {
		env = _G,
		compilerEnv = _G,

		readChunk = function(state)
			return self:_read_fennel_chunk(state)
		end,

		onValues = function(values)
			return self:_print_fennel_values(values)
		end,

		onError = function(err_type, err, lua_source)
			return self:_print_fennel_error(err_type, err, lua_source)
		end,

		["view-opts"] = self:_fennel_view_opts(),
	}
end

function REPL:run()
	io.write("JNLCFD | type ,help for help, ,quit or ctrl-D to exit\n")

	self._quit = false
	self:_capture_globals_at_start()

	local fennel = self:_require_fennel()
	fennel.repl(self:_fennel_repl_options())
end

--
-- Built in commands
--

function REPL:_register_builtins()
	self:command("quit", function(_self, _)
		io.write("bye\n")
		_self._quit = true
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

		for k, _ in pairs(_self._registry) do
			user[#user + 1] = k
		end

		local seen = {}
		local dedup = {}

		for _, k in ipairs(user) do
			if not seen[k] then
				seen[k] = true
				dedup[#dedup + 1] = k
			end
		end

		table.sort(dedup)

		if #dedup == 0 then
			io.write("no user globals defined\n")
		else
			local p = _self:_printer()

			for _, k in ipairs(dedup) do
				local entry = _self._registry[k]
				local doc = entry and entry.doc or ""

				if doc ~= "" then
					p:columns(k, doc, {
						indent = "  ",
						left_width = 20,
						gap = "  ",
					})
				else
					p:line(string.format("  %s", k))
				end
			end
		end
	end, ",globals", "List user-defined globals and registered values")

	self:command("doc", function(_self, arg)
		local doc = require("jnl.doc")
		arg = arg:match("^%s*(.-)%s*$")

		local opts = {
			width = _self._help_width or 72,
		}

		if arg == "" then
			doc.dump_modules(opts)
		elseif arg == "all" then
			doc.dump_all(opts)
		else
			doc.dump_module(arg, opts)
		end
	end, ",doc [module|all]", "List documented modules, or show docs for one module")

	self:command("llm", function(_self, _)
		local llm = require("jnl.llm")
		io.write(llm.context_string({
			width = _self._help_width or 72,
		}))
	end, ",llm", "Print full JNLCFD coding context for an LLM")
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

function REPL:_help_overview()
	local p = self:_printer()

	p:blank()
	p:line("  Comma commands")
	p:line("  --------------")

	local names = {}
	for k in pairs(self._commands) do names[#names + 1] = k end
	table.sort(names)

	for _, name in ipairs(names) do
		local c = self._commands[name]

		p:columns(c.usage, c.doc, {
			indent = "  ",
			left_width = 24,
			gap = "  ",
		})
	end

	local reg_names = {}
	for k in pairs(self._registry) do reg_names[#reg_names + 1] = k end
	table.sort(reg_names)

	if #reg_names > 0 then
		p:blank()
		p:line("  Registered globals (,help <name> for detail)")
		p:line("  --------------------------------------------")

		for _, name in ipairs(reg_names) do
			local e = self._registry[name]

			p:columns(name, e.doc, {
				indent = "  ",
				left_width = 24,
				gap = "  ",
			})
		end
	end

	p:blank()
	p:line("  ctrl-D or ,quit to exit")
	p:blank()
end

function REPL:_help_topic(name)
	local p = self:_printer()

	local entry = self._registry[name]
	if entry then
		p:blank()
		p:line("  " .. name)

		if entry.doc ~= "" then
			p:wrap("  ", "  ", entry.doc)
		end

		p:line("  type: " .. type(entry.value))
		p:blank()
		return
	end

	local cmd = self._commands[name]
	if cmd then
		p:blank()
		p:line("  " .. cmd.usage)

		if cmd.doc ~= "" then
			p:wrap("  ", "  ", cmd.doc)
			p:blank()
		end

		return
	end

	p:line(string.format("no help for '%s'", name))
end

function REPL.llm_string(opts)
	local llm = require("jnl.llm")
	return llm.context_string(opts or {})
end

function REPL.llm(opts)
	io.write(REPL.llm_string(opts or {}))
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

--
-- API
--

REPL._api = {
	new = {
		args = "",
		ret = "Repl",
		doc = "Create a new REPL instance with built-in commands registered",
	},
	script_summary = {
		args = "script_path:string",
		ret = "nil",
		doc = "Print globals that a script introduced",
	},
	llm_string = {
		args = "opts:table?",
		ret = "string",
		doc = "Return full JNLCFD coding context for LLMs",
	},
	llm = {
		args = "opts:table?",
		ret = "nil",
		doc = "Print full JNLCFD coding context for LLMs",
	},
}

REPL._types = {
	Repl = {
		kind = "table",
		constructor = "jnl.repl.new",
		doc = "Configurable Fennel REPL object",
		methods = {
			register = {
				args = "name:string, value:any, doc:string?",
				ret = "nil",
				doc = "Expose a value as a global and add it to the help system",
			},
			command = {
				args = "name:string, fn:function, usage:string?, doc:string?",
				ret = "nil",
				doc = "Register a custom comma command",
			},
			run = {
				args = "",
				ret = "nil",
				doc = "Start the Fennel REPL loop",
			},
		},
	},
}

return REPL
