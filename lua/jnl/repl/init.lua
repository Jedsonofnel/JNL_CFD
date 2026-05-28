-- jnl/repl/init.lua - Configurable REPL for the JNL suite
-- <jed@nelson.ac> // 2026-05-21

local Printer = require("jnl.repl.printer")

local REPL = {}
REPL.__index = REPL

REPL._doc = "Configurable Fennel REPL with comma commands and help system"

REPL._doc_subsection = {
	"Use jnl.repl.new() in interactive scripts, register useful values with repl:register, then end with return repl:run().",
	"The REPL evaluates Fennel input, even when the startup script itself is written in Lua.",
	"Registered names should be user-facing and Fennel-friendly; prefer names like show-mesh while optionally adding Lua-style aliases.",
	"Comma commands are for REPL control and discovery; registered globals are for user-callable demo functions and objects.",
	"Scripts can call repl:usage(text_or_fn) to provide a study-specific ,usage guide alongside the general ,help command.",
}

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

local CONTROL = {
	state = "idle",
}

-- Forward declarations for local helpers used by command tables.
local trim
local print_help_overview
local print_help_topic
local print_user_globals

local BUILTIN_VALUES = {
	{
		name = "pp",
		doc = "Pretty-print a Lua/Fennel value: (pp value)",
		value = function(repl)
			return function(value, opts)
				return repl:pp(value, opts)
			end
		end,
	},
	{
		name = "remember",
		doc = "Store a value in a named REPL special, e.g. (remember \"*last-run*\" result)",
		value = function(repl)
			return function(name, value, label)
				return repl:special(name, value, label)
			end
		end,
	},
}

local BUILTIN_COMMANDS = {
	{
		name = "usage",
		usage = ",usage",
		doc = "Show study-specific workflow, entry points, and options",
		fn = function(repl, _)
			repl:print_usage()
		end,
	},
	{
		name = "quit",
		usage = ",quit",
		doc = "Exit the REPL",
		fn = function(repl, _)
			io.write("bye\n")
			repl._quit = true
			CONTROL.state = "stopping"
		end,
	},
	{
		name = "help",
		usage = ",help [topic]",
		doc = "Show help. ,help <name> for a specific registered value or command",
		fn = function(repl, arg)
			arg = trim(arg)
			if arg == "" then
				print_help_overview(repl)
			else
				print_help_topic(repl, arg)
			end
		end,
	},
	{
		name = "globals",
		usage = ",globals",
		doc = "List user-defined globals and registered values",
		fn = function(repl, _)
			print_user_globals(repl)
		end,
	},
	{
		name = "doc",
		usage = ",doc [module|all]",
		doc = "List documented modules, or show docs for one module",
		fn = function(repl, arg)
			local doc = require("jnl.doc")
			arg = trim(arg)

			local opts = { width = repl._help_width or 72 }

			if arg == "" then
				doc.dump_modules(opts)
			elseif arg == "all" then
				doc.dump_all(opts)
			else
				doc.dump_module(arg, opts)
			end
		end,
	},
	{
		name = "llm",
		usage = ",llm",
		doc = "Print full JNLCFD coding context for an LLM",
		fn = function(repl, _)
			local llm = require("jnl.llm")
			io.write(llm.context_string({
				width = repl._help_width or 72,
			}))
		end,
	},
}

--
-- Basic helpers
--

trim = function(s)
	return (s or ""):match("^%s*(.-)%s*$")
end

local function starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

local function is_top_level(state)
	return not (state and state["stack-size"] and state["stack-size"] > 0)
end

local function is_result_name(name)
	return type(name) == "string"
		and (name == "*_" or name:match("^%*%d+$") ~= nil)
end

local function is_special_name(name)
	return type(name) == "string"
		and name:match("^%*[%w%-_]+%*$") ~= nil
		and not is_result_name(name)
end

local function repl_message(message)
	io.write(";; ")
	io.write(message)
	io.write("\n")
end

local function append_sorted_keys(out, t)
	for k in pairs(t) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

local function dedup_sorted(names)
	local seen = {}
	local out = {}

	for _, name in ipairs(names) do
		if not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end

	table.sort(out)
	return out
end

local function require_fennel()
	local ok, fennel = pcall(require, "fennel")

	if not ok then
		error("fennel not available; install/require fennel before starting REPL")
	end

	return fennel
end

local function default_readline(prompt)
	local read = readline or function(p)
		io.write(p)
		io.flush()
		return io.read("l")
	end

	return read(prompt)
end

local function printer_for(repl, opts)
	opts = opts or {}

	return Printer.new({
		width = opts.width or repl._help_width or 72,
		out = opts.out or function(s)
			io.write(s)
		end,
	})
end

--
-- Cooperative Ctrl-C support
--

local function cancel_seen()
	local f = rawget(_G, "__jnl_repl_cancel_seen")
	return type(f) == "function" and f()
end

local function cancel_clear()
	local f = rawget(_G, "__jnl_repl_cancel_clear")
	if type(f) == "function" then
		f()
	end
end

local function enter_reading()
	CONTROL.state = "reading"
	cancel_clear()
end

local function enter_evaluating()
	CONTROL.state = "evaluating"
	cancel_clear()
end

local function enter_idle()
	CONTROL.state = "idle"
	cancel_clear()
end

--
-- Value rendering
--

local function fennel_view_opts(repl)
	return {
		["line-length"] = repl._help_width or 72,
		depth = 8,
	}
end

local function fennel_view(repl, value, opts)
	local fennel = repl._fennel

	if not fennel then
		local ok, f = pcall(require, "fennel")
		if ok then fennel = f end
	end

	local view = fennel and fennel.view
	if not view then
		return tostring(value)
	end

	opts = opts or fennel_view_opts(repl)
	local ok_call, rendered = pcall(view, value, opts)
	return ok_call and rendered or tostring(value)
end

local function view_value(repl, value, opts)
	local mt = type(value) == "table" and getmetatable(value)
	if mt and mt.__tostring then
		return tostring(value)
	end

	return fennel_view(repl, value, opts)
end

local function print_rendered_values(values)
	for _, rendered in ipairs(values) do
		io.write(rendered)
		io.write("\n")
	end

	enter_reading()
end

--
-- Help and discovery
--

local function registered_names(repl)
	return append_sorted_keys({}, repl._registry)
end

local function command_names(repl)
	return append_sorted_keys({}, repl._commands)
end

local function user_global_names(repl)
	local names = {}

	for k, _ in pairs(_G) do
		if not STDLIB[k]
			and not is_result_name(k)
			and not is_special_name(k)
			and not (repl._globals_at_start and repl._globals_at_start[k])
		then
			names[#names + 1] = k
		end
	end

	for k, _ in pairs(repl._registry) do
		names[#names + 1] = k
	end

	return dedup_sorted(names)
end

print_user_globals = function(repl)
	local names = user_global_names(repl)

	if #names == 0 then
		io.write("no user globals defined\n")
		return
	end

	local p = printer_for(repl)

	for _, name in ipairs(names) do
		local entry = repl._registry[name]
		local doc = entry and entry.doc or ""

		if doc ~= "" then
			p:columns(name, doc, {
				indent = "  ",
				left_width = 20,
				gap = "  ",
			})
		else
			p:line(string.format("  %s", name))
		end
	end
end

print_help_overview = function(repl)
	local p = printer_for(repl)

	p:blank()
	p:line("  Comma commands")
	p:line("  --------------")

	for _, name in ipairs(command_names(repl)) do
		local c = repl._commands[name]

		p:columns(c.usage, c.doc, {
			indent = "  ",
			left_width = 24,
			gap = "  ",
		})
	end

	local reg_names = registered_names(repl)

	if #reg_names > 0 then
		p:blank()
		p:line("  Registered globals (,help <name> for detail)")
		p:line("  --------------------------------------------")

		for _, name in ipairs(reg_names) do
			local e = repl._registry[name]

			p:columns(name, e.doc, {
				indent = "  ",
				left_width = 24,
				gap = "  ",
			})
		end
	end

	p:blank()
	p:line("  Fennel results are available as *1, *2, and *3")
	p:line("  Named specials may be stored as *name* using remember or repl:special")
	p:line("  Ctrl-C cancels running code; ctrl-D or ,quit exits")
	p:blank()
end

print_help_topic = function(repl, name)
	local p = printer_for(repl)

	if is_result_name(name) or is_special_name(name) then
		p:line(string.format("no help for '%s'", name))
		return
	end

	local entry = repl._registry[name]
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

	local cmd = repl._commands[name]
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

--
-- Comma commands
--

local function dispatch_command(repl, cmd, rest)
	local entry = repl._commands[cmd]
	if not entry then
		io.write(string.format(
			"unknown command: ,%s  (type ,help for a list)\n", cmd))
		return
	end

	entry.fn(repl, rest)
end

local function handle_comma_line(repl, line, state)
	if not is_top_level(state) then
		io.write("error: comma commands are only available at top level\n")
		return
	end

	local cmd, rest = line:match("^,(%S+)%s*(.*)")

	if cmd then
		dispatch_command(repl, cmd, rest or "")
	else
		io.write("error: bare comma — did you mean ,help?\n")
	end
end

local function register_builtins(repl)
	for _, spec in ipairs(BUILTIN_VALUES) do
		repl:register(spec.name, spec.value(repl), spec.doc)
	end

	for _, spec in ipairs(BUILTIN_COMMANDS) do
		repl:command(spec.name, spec.fn, spec.usage, spec.doc)
	end
end

--
-- Fennel REPL integration
--

local function fennel_prompt(_, state)
	if state and state["stack-size"] and state["stack-size"] > 0 then
		return ".... "
	end

	return "jnl> "
end

local function read_fennel_chunk(repl, state)
	enter_reading()

	while true do
		if repl._quit then
			CONTROL.state = "stopping"
			return nil
		end

		local line = default_readline(fennel_prompt(repl, state))

		if line == nil then
			io.write("\n")
			CONTROL.state = "stopping"
			return nil
		end

		line = trim(line)

		if line == "" then
			-- Ignore blank lines.
		elseif starts_with(line, ",") then
			handle_comma_line(repl, line, state)
		else
			enter_evaluating()
			return line .. "\n"
		end
	end
end

local function print_fennel_error(err_type, err, _)
	io.write(string.format("error [%s]: %s\n", err_type, tostring(err)))
	enter_reading()
end

local function capture_globals_at_start(repl)
	repl._globals_at_start = {}

	for k, _ in pairs(_G) do
		repl._globals_at_start[k] = true
	end
end

local function fennel_repl_options(repl)
	return {
		env = _G,
		compilerEnv = _G,

		-- Let dynamically-created globals such as *last-run* be visible
		-- without predeclaring them before fennel.repl starts.
		allowedGlobals = false,
		["global-mangle"] = false,

		readChunk = function(state)
			return read_fennel_chunk(repl, state)
		end,

		-- onValues receives already-rendered strings.
		onValues = print_rendered_values,

		onError = print_fennel_error,

		pp = function(value, opts)
			return view_value(repl, value, opts)
		end,

		["view-opts"] = fennel_view_opts(repl),
	}
end

local function print_welcome()
	repl_message("JNLCFD repl - ,help commands - ,usage guide - Ctrl-C cancels - ctrl-D exits")
end

--
-- Constructor
--

function REPL.new()
	local self = setmetatable({
		_registry = {},
		_commands = {},
		_special_names = {},
		_help_width = 80,
	}, REPL)

	register_builtins(self)
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
		fn = fn,
		usage = usage or ("," .. name),
		doc = doc or "",
	}
end

function REPL:usage(spec)
	self._usage = spec
end

function REPL:usage_string()
	if type(self._usage) == "function" then
		return self._usage(self)
	end

	if type(self._usage) == "string" then
		return self._usage
	end

	if type(self._usage) == "table" and type(self._usage.string) == "function" then
		return self._usage:string()
	end

	if type(self._usage) == "table" and type(self._usage.usage_string) == "function" then
		return self._usage:usage_string()
	end

	return "No study-specific usage has been registered.\nUse ,help for REPL commands.\n"
end

function REPL:print_usage()
	local s = self:usage_string()
	io.write(s)
	if s:sub(-1) ~= "\n" then
		io.write("\n")
	end
end

function REPL:pp(value, opts)
	io.write(fennel_view(self, value, opts))
	io.write("\n")
	return value
end

function REPL:special(name, value, label)
	if not is_special_name(name) then
		error("special REPL names should look like *name*, e.g. *last-result*")
	end

	_G[name] = value
	self._special_names[name] = true

	if label and label ~= "" then
		repl_message(string.format("%s -> %s", label, name))
	else
		repl_message(string.format("stored -> %s", name))
	end

	return value
end

function REPL:run()
	print_welcome()

	self._quit = false
	capture_globals_at_start(self)
	enter_reading()

	self._fennel = require_fennel()
	self._fennel.repl(fennel_repl_options(self))

	enter_idle()
end

--
-- Module-level helpers
--

function REPL.is_cancelled()
	return CONTROL.state == "evaluating" and cancel_seen()
end

--
-- Convenience: post-script summary
--

---Print globals that a script introduced, for the "ran <script>" summary.
function REPL.script_summary(script_path)
	local user_globals = {}

	for k, _ in pairs(_G) do
		if not STDLIB[k]
			and not is_result_name(k)
			and not is_special_name(k)
		then
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

function REPL.llm_string(opts)
	local llm = require("jnl.llm")
	return llm.context_string(opts or {})
end

function REPL.llm(opts)
	io.write(REPL.llm_string(opts or {}))
end

-- API

REPL._api = {
	new = {
		args = "",
		ret = "Repl",
		doc = "Create a new REPL instance with built-in commands registered",
	},
	is_cancelled = {
		args = "",
		ret = "boolean",
		doc = "Return true if Ctrl-C has requested cancellation of the active REPL evaluation",
	},
	special = {
		args = "name:string, value:any, label:string?",
		ret = "any",
		doc = "Store a value in a named REPL special such as *last-run* and return it",
	},
	script_summary = {
		args = "script_path:string",
		ret = "nil",
		doc = "Print globals that a script introduced",
	},
	llm_string = {
		args = "opts:table?",
		ret = "string",
		doc = "Return full JNL coding context for LLMs",
	},
	llm = {
		args = "opts:table?",
		ret = "nil",
		doc = "Print full JNL coding context for LLMs",
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
			usage = {
				args = "spec:string|table|function",
				ret = "nil",
				doc = "Register study-specific usage text or a usage provider for ,usage",
			},
			usage_string = {
				args = "",
				ret = "string",
				doc = "Return registered study-specific usage text",
			},
			print_usage = {
				args = "",
				ret = "nil",
				doc = "Print registered study-specific usage text",
			},
			pp = {
				args = "value:any, opts:table?",
				ret = "any",
				doc = "Pretty-print a Lua/Fennel value and return it",
			},
			special = {
				args = "name:string, value:any, label:string?",
				ret = "any",
				doc = "Store a value in a named REPL special such as *last-run* and return it",
			},
		},
	},
}

return REPL
