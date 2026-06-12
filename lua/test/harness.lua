-- test/harness.lua
-- single-file test harness: describe/it/expect + filesystem discovery
-- requires: POSIX ls or Windows dir (via io.popen)

local M = {}

--
-- Platform
--

local is_windows = package.config:sub(1, 1) == "\\"
local sep = is_windows and "\\" or "/"

local function join(a, b)
	return a:gsub("[/\\]$", "") .. sep .. b
end

local function list_dir(path)
	local cmd = is_windows
		and string.format('dir /b /a "%s" 2>nul', path)
		or string.format("ls -1a '%s' 2>/dev/null", path)

	local handle = io.popen(cmd)

	if not handle then
		return {}
	end

	local entries = {}

	for line in handle:lines() do
		if line ~= "." and line ~= ".." then
			entries[#entries + 1] = line
		end
	end

	handle:close()

	return entries
end

local function is_dir(path)
	local cmd = is_windows
		and string.format(
			'if exist "%s\\" (echo yes) else (echo no)',
			path
		)
		or string.format(
			"test -d '%s' && echo yes || echo no",
			path
		)

	local handle = io.popen(cmd)

	if not handle then
		return false
	end

	local result = handle:read("*l")

	handle:close()

	return result and result:find("yes", 1, true) ~= nil
end

local function this_file_dir()
	local source = debug.getinfo(1, "S").source
	local path = source:match("^@(.+)$") or source

	return path:match("^(.+)[/\\][^/\\]+$") or "."
end

local function infer_lua_root()
	local source = (
		debug.getinfo(1, "S").source or ""
	):match("^@(.+)$") or ""

	for entry in package.path:gmatch("[^;]+") do
		local root = entry:match("^(.-)%?")

		if root
			and root ~= ""
			and source:sub(1, #root) == root
		then
			return root:gsub("[/\\]$", "")
		end
	end

	return nil
end

local function path_to_module(path, lua_root)
	path = path:gsub("^%.[/\\]", "")

	if lua_root then
		local prefix = lua_root:gsub("[/\\]$", "") .. sep

		if path:sub(1, #prefix) == prefix then
			path = path:sub(#prefix + 1)
		end
	else
		for entry in package.path:gmatch("[^;]+") do
			local root = entry:match("^(.-)%?")

			if root
				and root ~= ""
				and path:sub(1, #root) == root
			then
				path = path:sub(#root + 1)
				break
			end
		end
	end

	return path
		:gsub("%.lua$", "")
		:gsub("[/\\]", ".")
end

local function discover(dir, suffix, out)
	suffix = suffix or "_test.lua"
	out = out or {}

	local entries = list_dir(dir)

	table.sort(entries)

	for _, entry in ipairs(entries) do
		local full = join(dir, entry)

		if is_dir(full) then
			discover(full, suffix, out)
		elseif entry:sub(- #suffix) == suffix then
			out[#out + 1] = full
		end
	end

	return out
end

--
-- State
--

local root = {
	passed = 0,
	failed = 0,
	skipped = 0,
}

M.root = root

local blocks = {}
local current = nil

local suite_before_each = {}
local suite_after_each = {}

--
-- Collection
--

--- Group related tests.
---
--- The callback is called immediately to collect tests and block-level hooks.
---@param name string Block name.
---@param fn fun() Collection callback.
function M.describe(name, fn)
	assert(
		type(name) == "string" and name ~= "",
		"h.describe: name must be a non-empty string"
	)

	assert(
		type(fn) == "function",
		"h.describe: callback must be a function"
	)

	local block = {
		name = name,
		tests = {},
		before_each = {},
		after_each = {},
	}

	blocks[#blocks + 1] = block

	local previous = current
	current = block

	fn()

	current = previous
end

--- Define a test case in the enclosing describe block.
---@param name string Test name.
---@param fn fun() Test callback.
function M.it(name, fn)
	assert(
		current,
		"h.it() must be called inside h.describe()"
	)

	assert(
		type(fn) == "function",
		"h.it: callback must be a function"
	)

	current.tests[#current.tests + 1] = {
		name = name,
		fn = fn,
		skip = false,
	}
end

--- Define a skipped test with an optional reason.
---@param name string Test name.
---@param reason? string Skip reason.
function M.xit(name, reason)
	assert(
		current,
		"h.xit() must be called inside h.describe()"
	)

	current.tests[#current.tests + 1] = {
		name = name,
		skip = true,
		reason = reason,
	}
end

--- Register setup to run before each test.
---
--- Outside a describe block, the hook is suite-wide. Inside a describe block,
--- the hook applies only to that block. Multiple hooks are retained and run in
--- registration order.
---@param fn fun() Setup callback.
function M.before_each(fn)
	assert(
		type(fn) == "function",
		"h.before_each: callback must be a function"
	)

	local hooks = current
		and current.before_each
		or suite_before_each

	hooks[#hooks + 1] = fn
end

--- Register cleanup to run after each test.
---
--- Outside a describe block, the hook is suite-wide. Inside a describe block,
--- the hook applies only to that block. Multiple hooks are retained and run in
--- reverse registration order.
---@param fn fun() Cleanup callback.
function M.after_each(fn)
	assert(
		type(fn) == "function",
		"h.after_each: callback must be a function"
	)

	local hooks = current
		and current.after_each
		or suite_after_each

	hooks[#hooks + 1] = fn
end

--
-- Expectations
--

local function fmt(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end

	if type(value) == "number" then
		return string.format("%g", value)
	end

	return tostring(value)
end

local ctx = {
	block = nil,
	test = {},
	failed = false,
	failures = {},
}

local function fail(message)
	message = message or "assertion failed"

	io.write(string.format(
		"\n  FAIL  %s\n        %s\n",
		ctx.test.name,
		message
	))

	ctx.failures[#ctx.failures + 1] = message
	ctx.failed = true
end

--- Begin a fluent assertion chain on a value.
---@param value any Actual value.
---@return table expectation
function M.expect(value)
	local expectation = {}

	function expectation.equals(expected)
		if value ~= expected then
			fail(string.format(
				"expected %s, got %s",
				fmt(expected),
				fmt(value)
			))
		end

		return expectation
	end

	function expectation.not_equals(expected)
		if value == expected then
			fail(string.format(
				"expected not %s",
				fmt(expected)
			))
		end

		return expectation
	end

	function expectation.is_nil(message)
		if value ~= nil then
			fail(message or string.format(
				"expected nil, got %s",
				fmt(value)
			))
		end

		return expectation
	end

	function expectation.is_not_nil(message)
		if value == nil then
			fail(message or "expected non-nil value")
		end

		return expectation
	end

	function expectation.is_truthy(message)
		if not value then
			fail(message or string.format(
				"expected truthy, got %s",
				fmt(value)
			))
		end

		return expectation
	end

	function expectation.is_falsy(message)
		if value then
			fail(message or string.format(
				"expected falsy, got %s",
				fmt(value)
			))
		end

		return expectation
	end

	function expectation.is_less_than(number, message)
		if not (
				type(value) == "number"
				and value < number
			) then
			fail(message or string.format(
				"expected < %s, got %s",
				fmt(number),
				fmt(value)
			))
		end

		return expectation
	end

	function expectation.is_greater_than(number, message)
		if not (
				type(value) == "number"
				and value > number
			) then
			fail(message or string.format(
				"expected > %s, got %s",
				fmt(number),
				fmt(value)
			))
		end

		return expectation
	end

	function expectation.contains(item)
		if type(value) ~= "table" then
			fail(string.format(
				"expected table, got %s",
				type(value)
			))

			return expectation
		end

		for _, entry in ipairs(value) do
			if entry == item then
				return expectation
			end
		end

		fail(string.format(
			"%s not found in list",
			fmt(item)
		))

		return expectation
	end

	function expectation.not_contains(item)
		if type(value) ~= "table" then
			fail(string.format(
				"expected table, got %s",
				type(value)
			))

			return expectation
		end

		for _, entry in ipairs(value) do
			if entry == item then
				fail(string.format(
					"%s found in list but should be absent",
					fmt(item)
				))

				return expectation
			end
		end

		return expectation
	end

	function expectation.throws(pattern)
		if type(value) ~= "function" then
			fail("expect.throws: value must be a function")
			return expectation
		end

		local ok, err = pcall(value)

		if ok then
			fail("expected an error but none was thrown")
		elseif pattern
			and not tostring(err):find(pattern, 1, true)
		then
			fail(string.format(
				"error %q did not match pattern %q",
				tostring(err),
				pattern
			))
		end

		return expectation
	end

	function expectation.not_throws()
		if type(value) ~= "function" then
			fail("expect.not_throws: value must be a function")
			return expectation
		end

		local ok, err = pcall(value)

		if not ok then
			fail("unexpected error: " .. tostring(err))
		end

		return expectation
	end

	return expectation
end

--
-- Hook execution
--

local function run_hook(hook, label, index)
	local failures_before = #ctx.failures
	local ok, err = pcall(hook)

	if not ok then
		fail(string.format(
			"%s hook %d: %s",
			label,
			index,
			tostring(err)
		))
	end

	return ok and #ctx.failures == failures_before
end

local function run_before_hooks(hooks, label)
	for index, hook in ipairs(hooks) do
		if not run_hook(hook, label, index) then
			return false
		end
	end

	return true
end

local function run_after_hooks(hooks, label)
	for index = #hooks, 1, -1 do
		run_hook(hooks[index], label, index)
	end
end

--
-- Execution
--

local function run_test(block, test)
	ctx.block = block
	ctx.test = test
	ctx.failed = false
	ctx.failures = {}

	local setup_ok = run_before_hooks(
		suite_before_each,
		"suite before_each"
	)

	if setup_ok then
		setup_ok = run_before_hooks(
			block.before_each,
			"before_each"
		)
	end

	if setup_ok then
		local ok, err = pcall(test.fn)

		if not ok then
			ctx.failed = true
			ctx.failures[#ctx.failures + 1] = tostring(err)
		end
	end

	-- Cleanup always runs, including after setup or test failures.
	run_after_hooks(
		block.after_each,
		"after_each"
	)

	run_after_hooks(
		suite_after_each,
		"suite after_each"
	)

	return not ctx.failed, ctx.failures
end

local function print_failures(all_failures)
	if #all_failures == 0 then
		return
	end

	io.write("\nFailures:\n")

	for _, failure in ipairs(all_failures) do
		io.write(string.format(
			"\n  %d) %s: %s\n",
			failure.n,
			failure.block,
			failure.test
		))

		for _, message in ipairs(failure.messages) do
			io.write(string.format(
				"     %s\n",
				message
			))
		end
	end
end

local function print_dots(results)
	local column = 0

	for _, result in ipairs(results) do
		io.write(result.char)

		column = column + 1

		if column % 72 == 0 then
			io.write("\n")
		end
	end

	io.write("\n")
end

local function collect_results()
	local results = {}
	local all_failures = {}

	for _, block in ipairs(blocks) do
		for _, test in ipairs(block.tests) do
			if test.skip then
				results[#results + 1] = {
					char = "S",
				}

				root.skipped = root.skipped + 1
			else
				local passed, failures = run_test(
					block,
					test
				)

				if passed then
					results[#results + 1] = {
						char = ".",
					}

					root.passed = root.passed + 1
				else
					results[#results + 1] = {
						char = "F",
					}

					root.failed = root.failed + 1

					all_failures[#all_failures + 1] = {
						n = #all_failures + 1,
						block = block.name,
						test = test.name,
						messages = failures,
					}
				end
			end
		end
	end

	return results, all_failures
end

--- Run all collected tests and exit unsuccessfully if any fail.
function M.run()
	local results, all_failures = collect_results()

	print_dots(results)
	print_failures(all_failures)

	local total = root.passed
		+ root.failed
		+ root.skipped

	io.write(string.format(
		"\n%d passed  %d failed  %d skipped  (%d total)\n",
		root.passed,
		root.failed,
		root.skipped,
		total
	))

	if root.failed > 0 then
		os.exit(1)
	end
end

--- Discover test files, require them, and run the collected tests.
---@param base_dir? string Root directory to scan.
---@param lua_root? string Lua source root used to derive module names.
function M.run_specs(base_dir, lua_root)
	base_dir = base_dir or this_file_dir()
	lua_root = lua_root or infer_lua_root()

	local files = discover(base_dir)

	if #files == 0 then
		io.write(string.format(
			"harness: no *_test.lua files found under %s\n",
			base_dir
		))

		return
	end

	io.write(string.format(
		"harness: found %d test file(s) under %s\n",
		#files,
		base_dir
	))

	for _, path in ipairs(files) do
		local module_name = path_to_module(
			path,
			lua_root
		)

		local ok, err = pcall(
			require,
			module_name
		)

		if not ok then
			io.write(string.format(
				"\nERROR loading %s:\n  %s\n",
				module_name,
				tostring(err)
			))

			root.failed = root.failed + 1
		end
	end

	M.run()
end

return M
