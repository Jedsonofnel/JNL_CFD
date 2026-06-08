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
	local h = io.popen(cmd)
	if not h then return {} end
	local entries = {}
	for line in h:lines() do
		if line ~= "." and line ~= ".." then
			entries[#entries + 1] = line
		end
	end
	h:close()
	return entries
end

local function is_dir(path)
	local cmd = is_windows
		and string.format('if exist "%s\\" (echo yes) else (echo no)', path)
		or string.format("test -d '%s' && echo yes || echo no", path)
	local h = io.popen(cmd)
	if not h then return false end
	local result = h:read("*l")
	h:close()
	return result and result:find("yes") ~= nil
end

local function this_file_dir()
	local src  = debug.getinfo(1, "S").source
	local path = src:match("^@(.+)$") or src
	return path:match("^(.+)[/\\][^/\\]+$") or "."
end

local function infer_lua_root()
	local src = (debug.getinfo(1, "S").source or ""):match("^@(.+)$") or ""
	for entry in package.path:gmatch("[^;]+") do
		local root = entry:match("^(.-)%?")
		if root and root ~= "" and src:sub(1, #root) == root then
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
			if root and root ~= "" and path:sub(1, #root) == root then
				path = path:sub(#root + 1)
				break
			end
		end
	end
	return path:gsub("%.lua$", ""):gsub("[/\\]", ".")
end

local function discover(dir, suffix, out)
	suffix        = suffix or "_test.lua"
	out           = out or {}
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
-- state
--

local root = { passed = 0, failed = 0, skipped = 0 }

M.root = root

local blocks = {}   -- ordered list of describe blocks
local current = nil -- describe block being collected

--
-- collection
--

---Group related tests. fn() is called immediately to collect it() calls.
---@param name string
---@param fn fun()
function M.describe(name, fn)
	local block         = {
		name        = name,
		tests       = {},
		before_each = nil,
		after_each  = nil,
	}
	blocks[#blocks + 1] = block
	local prev          = current
	current             = block
	fn()
	current = prev
end

---Define a single test case within a describe block.
---@param name string
---@param fn fun()
function M.it(name, fn)
	assert(current, "h.it() must be called inside h.describe()")
	current.tests[#current.tests + 1] = { name = name, fn = fn, skip = false }
end

---Skip a test with an optional reason.
---@param name string
---@param reason? string
function M.xit(name, reason)
	assert(current, "h.xit() must be called inside h.describe()")
	current.tests[#current.tests + 1] = { name = name, skip = true, reason = reason }
end

---Run fn before each it() in the enclosing describe block.
---@param fn fun()
function M.before_each(fn)
	assert(current, "h.before_each() must be called inside h.describe()")
	current.before_each = fn
end

---Run fn after each it() in the enclosing describe block.
---@param fn fun()
function M.after_each(fn)
	assert(current, "h.after_each() must be called inside h.describe()")
	current.after_each = fn
end

--
-- Expect
--

local function fmt(v)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) == "number" then return string.format("%g", v) end
	return tostring(v)
end

-- current test context for recording pass/fail without passing names everywhere
local ctx = { block = nil, test = {}, failed = false }

local function fail(msg)
	io.write(string.format("\n  FAIL  %s\n        %s\n", ctx.test.name, msg))
	ctx.failures = ctx.failures or {}
	ctx.failures[#ctx.failures + 1] = msg or "assertion failed"
	ctx.failed = true -- add this
end

---Begin a fluent assertion chain on value.
---@param value any
---@return table
function M.expect(value)
	local E = {}

	function E.equals(expected)
		if value ~= expected then
			fail(string.format("expected %s, got %s", fmt(expected), fmt(value)))
		end
		return E
	end

	function E.not_equals(expected)
		if value == expected then
			fail(string.format("expected not %s", fmt(expected)))
		end
		return E
	end

	function E.is_nil(msg)
		if value ~= nil then
			fail(msg or string.format("expected nil, got %s", fmt(value)))
		end
		return E
	end

	function E.is_not_nil(msg)
		if value == nil then
			fail(msg or "expected non-nil value")
		end
		return E
	end

	function E.is_truthy(msg)
		if not value then
			fail(msg or string.format("expected truthy, got %s", fmt(value)))
		end
		return E
	end

	function E.is_falsy(msg)
		if value then
			fail(msg or string.format("expected falsy, got %s", fmt(value)))
		end
		return E
	end

	function E.is_less_than(n, msg)
		if not (type(value) == "number" and value < n) then
			fail(msg or string.format("expected < %s, got %s", fmt(n), fmt(value)))
		end
		return E
	end

	function E.is_greater_than(n, msg)
		if not (type(value) == "number" and value > n) then
			fail(msg or string.format("expected > %s, got %s", fmt(n), fmt(value)))
		end
		return E
	end

	function E.contains(item)
		if type(value) ~= "table" then
			fail(string.format("expected table, got %s", type(value)))
			return E
		end
		for _, v in ipairs(value) do
			if v == item then
				return E
			end
		end
		fail(string.format("%s not found in list", fmt(item)))
		return E
	end

	function E.not_contains(item)
		if type(value) ~= "table" then
			fail(string.format("expected table, got %s", type(value)))
			return E
		end
		for _, v in ipairs(value) do
			if v == item then
				fail(string.format("%s found in list but should be absent", fmt(item)))
				return E
			end
		end
		return E
	end

	function E.throws(pattern)
		if type(value) ~= "function" then
			fail("expect.throws: value must be a function")
			return E
		end
		local ok, err = pcall(value)
		if ok then
			fail("expected an error but none was thrown")
		elseif pattern and not tostring(err):find(pattern, 1, true) then
			fail(string.format("error %q did not match pattern %q", tostring(err), pattern))
		end
		return E
	end

	function E.not_throws()
		if type(value) ~= "function" then
			fail("expect.not_throws: value must be a function")
			return E
		end
		local ok, err = pcall(value)
		if not ok then
			fail("unexpected error: " .. tostring(err))
		end
		return E
	end

	return E
end

--
-- Execution
--

local function run_test(block, test)
	ctx.block = block
	ctx.test = test
	ctx.failed = false
	ctx.failures = {}

	if block.before_each then
		local ok, err = pcall(block.before_each)
		if not ok then
			fail("before_each: " .. tostring(err))
			return false, ctx.failures
		end
	end

	local ok, err = pcall(test.fn)
	if block.after_each then pcall(block.after_each) end

	if not ok and not ctx.failed then
		ctx.failed = true
		ctx.failures[#ctx.failures + 1] = tostring(err)
	end

	return not ctx.failed, ctx.failures
end

local function print_failures(all_failures)
	if #all_failures == 0 then return end

	io.write("\nFailures:\n")
	for _, f in ipairs(all_failures) do
		io.write(string.format("\n  %d) %s: %s\n", f.n, f.block, f.test))
		for _, msg in ipairs(f.msgs) do
			io.write(string.format("     %s\n", msg))
		end
	end
end

local function print_dots(results)
	local col = 0
	for _, r in ipairs(results) do
		io.write(r.ch)
		col = col + 1
		if col % 72 == 0 then io.write("\n") end
	end
	io.write("\n")
end

local function collect_results()
	local results      = {}
	local all_failures = {}

	for _, block in ipairs(blocks) do
		for _, test in ipairs(block.tests) do
			if test.skip then
				results[#results + 1] = { ch = "S" }
				root.skipped = root.skipped + 1
			else
				local passed, failures = run_test(block, test)
				if passed then
					results[#results + 1] = { ch = "." }
					root.passed = root.passed + 1
				else
					results[#results + 1] = { ch = "F" }
					root.failed = root.failed + 1
					all_failures[#all_failures + 1] = {
						n     = #all_failures + 1,
						block = block.name,
						test  = test.name,
						msgs  = failures,
					}
				end
			end
		end
	end

	return results, all_failures
end

function M.run()
	local results, all_failures = collect_results()

	print_dots(results)
	print_failures(all_failures)

	local total = root.passed + root.failed + root.skipped
	io.write(string.format("\n%d passed  %d failed  %d skipped  (%d total)\n",
		root.passed, root.failed, root.skipped, total))

	if root.failed > 0 then os.exit(1) end
end

---Discover *_test.lua files under base_dir, require each, then run.
---@param base_dir? string  Root to scan; defaults to directory containing harness.lua.
---@param lua_root? string  Lua source root for module name derivation.
function M.run_specs(base_dir, lua_root)
	base_dir = base_dir or this_file_dir()
	lua_root = lua_root or infer_lua_root()

	local files = discover(base_dir)
	if #files == 0 then
		io.write(string.format("harness: no *_test.lua files found under %s\n", base_dir))
		return
	end

	io.write(string.format("harness: found %d test file(s) under %s\n", #files, base_dir))

	for _, path in ipairs(files) do
		local modname = path_to_module(path, lua_root)
		local ok, err = pcall(require, modname)
		if not ok then
			io.write(string.format("\nERROR loading %s:\n  %s\n", modname, tostring(err)))
			root.failed = root.failed + 1
		end
	end

	M.run()
end

return M
