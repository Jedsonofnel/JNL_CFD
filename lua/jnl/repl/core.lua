-- lua/jnl/repl/core.lua - Core JNL Fennel REPL implementation
-- <jed@nelson.ac> // 2026-06-12

local Commands = require("jnl.repl.commands")
local Help = require("jnl.repl.help")

--- Implement the JNL Fennel REPL object and evaluation loop.
---@private
local M = {}

---@alias ReplDocSpec
---| string
---| false
---| { doc:string?, from:string?, lookup:boolean? }

---@alias ReplUsageSpec
---| string
---| fun(repl: jnl.repl.Repl): string
---| table

--- A value registered with the REPL help system.
---@class jnl.repl.RegistryEntry
---@field value any
---@field doc string

--- A comma command registered with the REPL.
---@class jnl.repl.Command
---@field fn fun(repl: jnl.repl.Repl, arg: string)
---@field usage string
---@field doc string

--- A configurable JNL Fennel REPL instance.
---@class jnl.repl.Repl
---@field registry table<string, jnl.repl.RegistryEntry>
---@field commands table<string, jnl.repl.Command>
---@field help_width integer
---@field doc_index DocIndex?
---@field usage_spec ReplUsageSpec?
---@field globals_at_start table<string, boolean>
---@field fennel table?
---@field quit boolean
---@field started boolean
---@field running boolean
local Repl = {}
Repl.__index = Repl

local CONTROL = {
	state = "idle",
}

--
-- Host cancellation bridge
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

local function mark_repl_started()
	local callback = rawget(_G, "__jnl_repl_mark_started")

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
-- Basic helpers
--

local function trim(text)
	return (text or ""):match("^%s*(.-)%s*$")
end

local function starts_with(text, prefix)
	return text:sub(1, #prefix) == prefix
end

local function is_top_level(state)
	return not (
		state
		and state["stack-size"]
		and state["stack-size"] > 0
	)
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
	local read = rawget(_G, "readline")

	if type(read) == "function" then
		return read(prompt)
	end

	io.write(prompt)
	io.flush()

	return io.read("l")
end

local function repl_message(message)
	io.write(";; ")
	io.write(message)
	io.write("\n")
end

--
-- Value rendering
--

local function fennel_view_opts(repl)
	return {
		["line-length"] = repl.help_width,
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

	local ok, rendered = pcall(
		view,
		value,
		opts or fennel_view_opts(repl)
	)

	if ok then
		return rendered
	end

	return tostring(value)
end

local function view_value(repl, value, opts)
	local metatable = type(value) == "table"
		and getmetatable(value)

	if metatable and metatable.__tostring then
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
-- Commands and input
--

local function dispatch_command(repl, name, argument)
	local command = repl.commands[name]

	if not command then
		io.write(string.format(
			"unknown command: ,%s  (type ,help for a list)\n",
			name
		))
		return
	end

	command.fn(repl, argument)
end

local function handle_comma_line(repl, line, state)
	if not is_top_level(state) then
		io.write(
			"error: comma commands are only available at top level\n"
		)
		return
	end

	local command, argument = line:match("^,(%S+)%s*(.*)")

	if command then
		dispatch_command(repl, command, argument or "")
	else
		io.write("error: bare comma - did you mean ,help?\n")
	end
end

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
			repl:stop()
			return nil
		end

		line = trim(line)

		if line == "" then
			-- Ignore blank or interrupted prompt lines.
		elseif starts_with(line, ",") then
			handle_comma_line(repl, line, state)
		else
			enter_evaluating()
			return line .. "\n"
		end
	end
end

local function print_fennel_error(error_type, err)
	io.write(string.format(
		"error [%s]: %s\n",
		error_type,
		tostring(err)
	))

	enter_reading()
end

local function fennel_repl_options(repl)
	return {
		env = _G,
		compilerEnv = _G,

		allowedGlobals = false,
		["global-mangle"] = false,

		readChunk = function(state)
			return read_fennel_chunk(repl, state)
		end,

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

--
-- Construction
--

--- Create an independent JNL REPL.
---@param opts? table Construction options.
---@return jnl.repl.Repl repl
function M.new(opts)
	opts = opts or {}

	local repl = setmetatable({
		registry = {},
		commands = {},
		help_width = opts.width or 80,
		doc_index = nil,
		usage_spec = nil,
		globals_at_start = {},
		fennel = nil,
		quit = false,
		started = false,
		running = false,
	}, Repl)

	Commands.install(repl)
	repl.globals_at_start = Help.capture_globals()

	return repl
end

--
-- Public instance API
--

--- Expose a value as a global and register it with the help system.
---
--- When `doc` is omitted, the documentation index is searched for a uniquely
--- matching symbol, type, or module. A string is literal help text. A table may
--- contain `from` for explicit lookup or `doc` for literal text. Pass `false`
--- to suppress lookup.
---@param name string User-facing global name.
---@param value any Value to expose.
---@param doc? ReplDocSpec Documentation source.
---@return any value
function Repl:register(name, value, doc)
	assert(
		type(name) == "string" and name ~= "",
		"repl.register: name must be a non-empty string"
	)

	local description = Help.registration_doc(
		self,
		name,
		doc
	)

	self.registry[name] = {
		value = value,
		doc = description,
	}

	_G[name] = value

	return value
end

--- Register a custom comma command.
---@param name string Command name without the comma.
---@param fn fun(repl: jnl.repl.Repl, arg: string)
---@param usage? string Displayed command usage.
---@param doc? string Help text.
function Repl:command(name, fn, usage, doc)
	assert(
		type(name) == "string" and name ~= "",
		"repl.command: name must be a non-empty string"
	)

	assert(
		type(fn) == "function",
		"repl.command: callback must be a function"
	)

	self.commands[name] = {
		fn = fn,
		usage = usage or ("," .. name),
		doc = doc or "",
	}
end

--- Register study-specific usage text or a usage provider.
---@param spec ReplUsageSpec Usage source.
function Repl:usage(spec)
	self.usage_spec = spec
end

--- Return registered study-specific usage text.
---@return string text
function Repl:usage_string()
	local spec = self.usage_spec

	if type(spec) == "function" then
		return spec(self)
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

--- Print registered study-specific usage text.
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
---@param label? string|false Optional confirmation label; false suppresses output.
---@return any value
function Repl:special(name, value, label)
	if not Help.is_special_name(name) then
		error(
			"special REPL names should look like *name*, "
			.. "for example *last-result*"
		)
	end

	_G[name] = value

	if label == false then
		return value
	end

	if type(label) == "string" and label ~= "" then
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

--- Request that this REPL loop stops.
function Repl:stop()
	self.quit = true
	CONTROL.state = "stopping"
end

--- Start the Fennel REPL loop.
function Repl:run()
	if self.running then
		error("repl.run: this REPL is already running")
	end

	mark_repl_started()

	self.started = true
	self.running = true
	self.quit = false

	print_welcome()
	enter_reading()

	self.fennel = require_fennel()

	local ok, err = pcall(
		self.fennel.repl,
		fennel_repl_options(self)
	)

	self.running = false
	self.quit = true
	enter_idle()

	if not ok then
		error(err, 0)
	end
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
	local names = Help.script_global_names()

	print(string.format("ran %s", script_path))

	if #names > 0 then
		print("globals: " .. table.concat(names, ", "))
	else
		print("note: script set no globals")
	end
end

return M
