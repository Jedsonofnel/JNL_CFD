-- lua/jnl/repl/init.lua - Configurable Fennel REPL for the JNL suite
-- <jed@nelson.ac> // 2026-06-11

local Printer = require("jnl.repl.printer")

--- Provide a configurable Fennel REPL with comma commands, documentation,
--- cancellation, registered values, and study-specific usage.
local M = {}

--- A registered value exposed through the REPL.
---@class ReplRegistryEntry
---@field value any
---@field doc string

--- A comma command registered with the REPL.
---@class ReplCommand
---@field fn fun(repl: Repl, arg: string)
---@field usage string
---@field doc string

--- A configurable JNL Fennel REPL instance.
---@class Repl
---@field registry table<string, ReplRegistryEntry>
---@field commands table<string, ReplCommand>
---@field help_width integer
---@field doc_index DocIndex?
---@field usage_spec string|table|fun(repl: Repl): string|nil
---@field globals_at_start table<string, boolean>?
---@field fennel table?
---@field quit boolean
local Repl = {}
Repl.__index = Repl

--
-- Known host globals
--

local STDLIB = {
	_G = true,
	_VERSION = true,

	assert = true,
	collectgarbage = true,
	dofile = true,
	error = true,
	getmetatable = true,
	ipairs = true,
	load = true,
	loadfile = true,
	next = true,
	pairs = true,
	pcall = true,
	print = true,
	rawequal = true,
	rawget = true,
	rawlen = true,
	rawset = true,
	require = true,
	select = true,
	setmetatable = true,
	tonumber = true,
	tostring = true,
	type = true,
	warn = true,
	xpcall = true,

	coroutine = true,
	debug = true,
	io = true,
	math = true,
	os = true,
	package = true,
	string = true,
	table = true,
	utf8 = true,

	_script = true,
	readline = true,
	__jnl_repl_cancel_seen = true,
	__jnl_repl_cancel_clear = true,
	__jnl_repl_mark_started = true,
}

local CONTROL = {
	state = "idle",
}

--
-- Forward declarations
--

local trim
local documentation_index
local print_help_overview
local print_help_topic
local print_user_globals

--
-- Built-in values
--

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
		doc = "Store a named REPL special: (remember \"*last-run*\" result)",
		value = function(repl)
			return function(name, value, label)
				return repl:special(name, value, label)
			end
		end,
	},
}

--
-- Built-in comma commands
--

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
			repl.quit = true
			CONTROL.state = "stopping"
		end,
	},
	{
		name = "help",
		usage = ",help [topic]",
		doc = "Show help, or show details for a command or registered value",
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
		usage = ",doc [module|all|refresh]",
		doc = "List modules, show one module, print all docs, or rescan sources",
		fn = function(repl, arg)
			arg = trim(arg)

			if arg == "refresh" then
				repl.doc_index = nil
				documentation_index(repl)
				io.write("documentation index refreshed\n")
				return
			end

			local docs = documentation_index(repl)
			local opts = {
				width = repl.help_width or 72,
				types = "local",
			}

			if arg == "" then
				io.write(docs:render_modules(opts))
				return
			end

			if arg == "all" then
				docs:dump_all(opts)
				return
			end

			local ok, err = docs:dump_module(arg, opts)

			if not ok then
				io.write(tostring(err))
				io.write("\n")
			end
		end,
	},
	{
		name = "llm",
		usage = ",llm",
		doc = "Print JNL coding instructions, examples, and API documentation",
		fn = function(repl, _)
			local llm = require("jnl.doc.llm")

			io.write(llm.context_string({
				width = repl.help_width or 72,
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
	return not (
		state
		and state["stack-size"]
		and state["stack-size"] > 0
	)
end

local function is_result_name(name)
	return type(name) == "string"
		and (
			name == "*_"
			or name:match("^%*%d+$") ~= nil
		)
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

local function append_sorted_keys(out, values)
	for key in pairs(values) do
		out[#out + 1] = key
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
		error(
			"Fennel is unavailable; install or preload it before starting the REPL"
		)
	end

	return fennel
end

local function default_readline(prompt)
	local read = readline or function(text)
		io.write(text)
		io.flush()
		return io.read("l")
	end

	return read(prompt)
end

local function printer_for(repl, opts)
	opts = opts or {}

	return Printer.new({
		width = opts.width or repl.help_width or 72,
		out = opts.out or function(s)
			io.write(s)
		end,
	})
end

documentation_index = function(repl)
	if not repl.doc_index then
		local doc = require("jnl.doc")

		repl.doc_index = doc.scan({
			packages = { "jnl" },
		})
	end

	return repl.doc_index
end

--
-- Cooperative Ctrl-C support
--

local function cancel_seen()
	local callback = rawget(_G, "__jnl_repl_cancel_seen")

	return type(callback) == "function"
		and callback()
end

local function cancel_clear()
	local callback = rawget(_G, "__jnl_repl_cancel_clear")

	if type(callback) == "function" then
		callback()
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
		["line-length"] = repl.help_width or 72,
		depth = 8,
	}
end

local function fennel_view(repl, value, opts)
	local fennel = repl.fennel

	if not fennel then
		local ok, loaded = pcall(require, "fennel")

		if ok then
			fennel = loaded
		end
	end

	local view = fennel and fennel.view

	if not view then
		return tostring(value)
	end

	opts = opts or fennel_view_opts(repl)

	local ok, rendered = pcall(view, value, opts)

	if ok then
		return rendered
	end

	return tostring(value)
end

local function view_value(repl, value, opts)
	local mt = type(value) == "table"
		and getmetatable(value)

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
	return append_sorted_keys({}, repl.registry)
end

local function command_names(repl)
	return append_sorted_keys({}, repl.commands)
end

local function user_global_names(repl)
	local names = {}

	for name in pairs(_G) do
		if not STDLIB[name]
			and not is_result_name(name)
			and not is_special_name(name)
			and not (
				repl.globals_at_start
				and repl.globals_at_start[name]
			)
		then
			names[#names + 1] = name
		end
	end

	for name in pairs(repl.registry) do
		names[#names + 1] = name
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
		local entry = repl.registry[name]
		local doc = entry and entry.doc or ""

		if doc ~= "" then
			p:columns(name, doc, {
				indent = "  ",
				left_width = 20,
				gap = "  ",
			})
		else
			p:line("  " .. name)
		end
	end
end

print_help_overview = function(repl)
	local p = printer_for(repl)

	p:header("Comma commands", 2)

	for _, name in ipairs(command_names(repl)) do
		local command = repl.commands[name]

		p:columns(command.usage, command.doc, {
			indent = "  ",
			left_width = 26,
			gap = "  ",
		})
	end

	local names = registered_names(repl)

	if #names > 0 then
		p:header("Registered globals", 2)
		p:line("Use ,help <name> for details.")
		p:blank()

		for _, name in ipairs(names) do
			local entry = repl.registry[name]

			p:columns(name, entry.doc, {
				indent = "  ",
				left_width = 24,
				gap = "  ",
			})
		end
	end

	p:blank()
	p:line("  Fennel results are available as *1, *2, and *3")
	p:line("  Named specials may be stored as *name* with remember")
	p:line("  Ctrl-C once requests cancellation; twice forces it")
	p:line("  Ctrl-C at the prompt clears the line")
	p:line("  Ctrl-D or ,quit exits")
	p:blank()
end

print_help_topic = function(repl, name)
	local p = printer_for(repl)

	if is_result_name(name) or is_special_name(name) then
		p:line(string.format("no help for '%s'", name))
		return
	end

	local entry = repl.registry[name]

	if entry then
		p:header(name, 2)

		if entry.doc ~= "" then
			p:wrap("  ", "  ", entry.doc)
		end

		p:line("  type: " .. type(entry.value))
		p:blank()
		return
	end

	local command = repl.commands[name]

	if command then
		p:header(command.usage, 2)

		if command.doc ~= "" then
			p:wrap("  ", "  ", command.doc)
			p:blank()
		end

		return
	end

	p:line(string.format("no help for '%s'", name))
end

--
-- Comma commands
--

local function dispatch_command(repl, name, rest)
	local command = repl.commands[name]

	if not command then
		io.write(string.format(
			"unknown command: ,%s  (type ,help for a list)\n",
			name
		))
		return
	end

	command.fn(repl, rest)
end

local function handle_comma_line(repl, line, state)
	if not is_top_level(state) then
		io.write(
			"error: comma commands are only available at top level\n"
		)
		return
	end

	local command, rest = line:match("^,(%S+)%s*(.*)")

	if command then
		dispatch_command(repl, command, rest or "")
	else
		io.write("error: bare comma - did you mean ,help?\n")
	end
end

local function register_builtins(repl)
	for _, spec in ipairs(BUILTIN_VALUES) do
		repl:register(
			spec.name,
			spec.value(repl),
			spec.doc
		)
	end

	for _, spec in ipairs(BUILTIN_COMMANDS) do
		repl:command(
			spec.name,
			spec.fn,
			spec.usage,
			spec.doc
		)
	end
end

--
-- Fennel REPL integration
--

local function fennel_prompt(_, state)
	if state
		and state["stack-size"]
		and state["stack-size"] > 0
	then
		return ".... "
	end

	return "jnl> "
end

local function read_fennel_chunk(repl, state)
	enter_reading()

	while true do
		if repl.quit then
			CONTROL.state = "stopping"
			return nil
		end

		local line = default_readline(
			fennel_prompt(repl, state)
		)

		if line == nil then
			io.write("\n")
			repl.quit = true
			CONTROL.state = "stopping"
			return nil
		end

		line = trim(line)

		if line == "" then
			-- Ignore blank and interrupted prompt lines.
		elseif starts_with(line, ",") then
			handle_comma_line(repl, line, state)
		else
			enter_evaluating()
			return line .. "\n"
		end
	end
end

local function print_fennel_error(err_type, err, _)
	io.write(string.format(
		"error [%s]: %s\n",
		err_type,
		tostring(err)
	))

	enter_reading()
end

local function capture_globals_at_start(repl)
	repl.globals_at_start = {}

	for name in pairs(_G) do
		repl.globals_at_start[name] = true
	end
end

local function fennel_repl_options(repl)
	return {
		env = _G,
		compilerEnv = _G,

		-- Dynamically created names such as *last-run* remain visible.
		allowedGlobals = false,
		["global-mangle"] = false,

		readChunk = function(state)
			return read_fennel_chunk(repl, state)
		end,

		-- Fennel passes already-rendered strings here.
		onValues = print_rendered_values,
		onError = print_fennel_error,

		pp = function(value, opts)
			return view_value(repl, value, opts)
		end,

		["view-opts"] = fennel_view_opts(repl),
	}
end

local function print_welcome()
	repl_message(
		"JNL REPL - ,help commands - ,usage guide - "
		.. "Ctrl-C cancels - Ctrl-D exits"
	)
end

local function mark_repl_started()
	local callback = rawget(_G, "__jnl_repl_mark_started")

	if type(callback) == "function" then
		callback()
	end
end

--
-- Constructor
--

--- Create a REPL with the standard JNL commands and registered values.
---@return Repl repl
function M.new()
	local repl = setmetatable({
		registry = {},
		commands = {},
		help_width = 80,
		doc_index = nil,
		usage_spec = nil,
		globals_at_start = nil,
		fennel = nil,
		quit = false,
	}, Repl)

	register_builtins(repl)
	return repl
end

--
-- Public instance API
--

--- Expose a value as a global and add it to the help system.
---@param name string User-facing global name.
---@param value any Value to expose.
---@param doc? string Help text.
function Repl:register(name, value, doc)
	self.registry[name] = {
		value = value,
		doc = doc or "",
	}

	_G[name] = value
end

--- Register a custom comma command.
---@param name string Command name without the comma.
---@param fn fun(repl: Repl, arg: string) Command callback.
---@param usage? string Displayed command usage.
---@param doc? string Help text.
function Repl:command(name, fn, usage, doc)
	self.commands[name] = {
		fn = fn,
		usage = usage or ("," .. name),
		doc = doc or "",
	}
end

--- Register study-specific usage text or a usage provider.
---@param spec string|table|fun(repl: Repl): string Usage source.
function Repl:usage(spec)
	self.usage_spec = spec
end

--- Return the registered study-specific usage text.
---@return string text
function Repl:usage_string()
	local spec = self.usage_spec

	if type(spec) == "function" then
		return spec(self) or ""
	end

	if type(spec) == "string" then
		return spec
	end

	if type(spec) == "table"
		and type(spec.string) == "function"
	then
		return spec:string()
	end

	if type(spec) == "table"
		and type(spec.usage_string) == "function"
	then
		return spec:usage_string()
	end

	return table.concat({
		"No study-specific usage has been registered.",
		"Use ,help for REPL commands.",
		"",
	}, "\n")
end

--- Print the registered study-specific usage text.
function Repl:print_usage()
	local text = self:usage_string()

	io.write(text)

	if text:sub(-1) ~= "\n" then
		io.write("\n")
	end
end

--- Pretty-print a Lua or Fennel value and return it unchanged.
---@param value any Value to print.
---@param opts? table Fennel view options.
---@return any value
function Repl:pp(value, opts)
	io.write(fennel_view(self, value, opts))
	io.write("\n")
	return value
end

--- Store a value in a named REPL special such as `*last-run*`.
---@param name string Special name surrounded by asterisks.
---@param value any Value to store.
---@param label? string Optional confirmation label.
---@return any value
function Repl:special(name, value, label)
	if not is_special_name(name) then
		error(
			"special REPL names should look like *name*, "
			.. "for example *last-result*"
		)
	end

	_G[name] = value

	if label and label ~= "" then
		repl_message(string.format(
			"%s -> %s",
			label,
			name
		))
	else
		repl_message("stored -> " .. name)
	end

	return value
end

--- Start the Fennel REPL loop.
function Repl:run()
	mark_repl_started()
	print_welcome()

	self.quit = false
	capture_globals_at_start(self)
	enter_reading()

	self.fennel = require_fennel()
	self.fennel.repl(fennel_repl_options(self))

	self.quit = true
	enter_idle()
end

--
-- Module-level helpers
--

--- Return true when Ctrl-C has requested cancellation of active evaluation.
---@return boolean cancelled
function M.is_cancelled()
	return CONTROL.state == "evaluating"
		and cancel_seen()
end

--- Print globals introduced by a script.
---@param script_path string Executed script path.
function M.script_summary(script_path)
	local user_globals = {}

	for name in pairs(_G) do
		if not STDLIB[name]
			and not is_result_name(name)
			and not is_special_name(name)
		then
			user_globals[#user_globals + 1] = name
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

--- Return the complete JNL coding context for a language model.
---@param opts? table Context rendering options.
---@return string text
function M.llm_string(opts)
	local llm = require("jnl.doc.llm")
	return llm.context_string(opts or {})
end

--- Print the complete JNL coding context for a language model.
---@param opts? table Context rendering options.
function M.llm(opts)
	io.write(M.llm_string(opts or {}))
end

return M
