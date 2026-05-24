-- test/harness.lua - testing utilities
-- <jed@nelson.ac> // 2026-05-24

local M = {}

--
-- Formatting helpers
--

local function pad_right(s, n)
	local len = utf8 and (utf8.len(s) or #s) or #s
	return s .. string.rep(" ", math.max(0, n - len))
end

local function fmt_value(v)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) == "number" then return string.format("%g", v) end
	if type(v) == "boolean" then return tostring(v) end
	if type(v) == "table" then
		local parts = {}
		for i, x in ipairs(v) do parts[i] = fmt_value(x) end
		if #parts > 0 then return "{" .. table.concat(parts, ", ") .. "}" end
		return tostring(v)
	end
	return tostring(v)
end

M.fmt_value = fmt_value

--
-- Suite - collects results
--

local Suite = {}
Suite.__index = Suite

function Suite.new(name, root)
	return setmetatable({
		name     = name,
		root     = root, -- optional shared Root; if nil uses self
		passed   = 0,
		failed   = 0,
		skipped  = 0,
		_results = {},
	}, Suite)
end

local function suite_record(self, status, name, msg)
	self._results[#self._results + 1] = {
		status = status, name = name, msg = msg
	}
	if status == "pass" then
		self.passed = self.passed + 1
		if self.root then self.root.passed = self.root.passed + 1 end
	elseif status == "fail" then
		if self._next_diag then
			self._next_diag()
		end
		self.failed = self.failed + 1
		if self.root then self.root.failed = self.root.failed + 1 end
	elseif status == "skip" then
		self.skipped = self.skipped + 1
		if self.root then self.root.skipped = self.root.skipped + 1 end
	end
	self._next_diag = nil
end

-- add a diagnostic function to run on failure
function Suite:diag(fn)
	self._next_diag = fn
end

-- Low-level: pass a boolean condition directly.
-- msg is shown on failure.
function Suite:check(name, cond, msg)
	if cond then
		io.write(string.format("ok   %s\n", name))
		suite_record(self, "pass", name, nil)
	else
		io.write(string.format("FAIL %s\n", name))
		if msg then io.write(string.format("     %s\n", msg)) end
		suite_record(self, "fail", name, msg or "assertion failed")
	end
end

-- Equality check with a diff line on failure.
function Suite:eq(name, got, expected)
	if got == expected then
		io.write(string.format("ok   %s\n", name))
		suite_record(self, "pass", name, nil)
	else
		local msg = string.format("expected %s, got %s",
			fmt_value(expected), fmt_value(got))
		io.write(string.format("FAIL %s\n     %s\n", name, msg))
		suite_record(self, "fail", name, msg)
	end
end

-- Greater-than check.
function Suite:gt(name, got, threshold, msg)
	local cond = type(got) == "number" and got > threshold
	self:check(name, cond,
		msg or string.format("expected > %s, got %s",
			fmt_value(threshold), fmt_value(got)))
end

-- Less-than check.
function Suite:lt(name, got, threshold, msg)
	local cond = type(got) == "number" and got < threshold
	self:check(name, cond,
		msg or string.format("expected < %s, got %s",
			fmt_value(threshold), fmt_value(got)))
end

-- Check that a value is not nil.
function Suite:exists(name, got, msg)
	self:check(name, got ~= nil,
		msg or string.format("expected non-nil, got nil"))
end

-- Check that a table contains at least the given keys.
function Suite:has_keys(name, tbl, keys)
	if type(tbl) ~= "table" then
		self:check(name, false, "expected a table, got " .. type(tbl))
		return
	end
	local missing = {}
	for _, k in ipairs(keys) do
		if tbl[k] == nil then missing[#missing + 1] = tostring(k) end
	end
	self:check(name, #missing == 0,
		"missing keys: " .. table.concat(missing, ", "))
end

-- Check that a list contains an item (by equality).
function Suite:contains(name, list, item)
	if type(list) ~= "table" then
		self:check(name, false, "expected a table, got " .. type(list))
		return
	end
	for _, v in ipairs(list) do
		if v == item then
			self:check(name, true); return
		end
	end
	self:check(name, false,
		fmt_value(item) .. " not found in list")
end

-- Check that a list does NOT contain an item.
function Suite:not_contains(name, list, item)
	if type(list) ~= "table" then
		self:check(name, false, "expected a table, got " .. type(list))
		return
	end
	for _, v in ipairs(list) do
		if v == item then
			self:check(name, false,
				fmt_value(item) .. " found in list but should be absent")
			return
		end
	end
	self:check(name, true)
end

-- Check that a callable throws an error matching an optional pattern.
function Suite:throws(name, fn, pattern)
	local ok, err = pcall(fn)
	if ok then
		self:check(name, false, "expected an error but none was thrown")
		return
	end
	if pattern then
		local matched = tostring(err):find(pattern, 1, true)
		self:check(name, matched ~= nil,
			string.format("error %q did not match pattern %q",
				tostring(err), pattern))
	else
		self:check(name, true)
	end
end

-- Check that a callable does NOT throw.
function Suite:no_throw(name, fn)
	local ok, err = pcall(fn)
	self:check(name, ok,
		ok and nil or ("unexpected error: " .. tostring(err)))
end

-- Mark a test as skipped with a reason.
function Suite:skip(name, reason)
	io.write(string.format("skip %s  (%s)\n", name, reason or "no reason"))
	suite_record(self, "skip", name, reason)
end

-- Print a summary line for this suite.
-- Returns true if all non-skipped tests passed.
function Suite:summary()
	local total = self.passed + self.failed + self.skipped
	io.write(string.format(
		"\n[%s]  %d passed  %d failed  %d skipped  (%d total)\n",
		self.name, self.passed, self.failed, self.skipped, total))
	return self.failed == 0
end

M.Suite = Suite

--
-- Root accumulator
--

local Root = {}
Root.__index = Root

function Root.new()
	return setmetatable({ passed = 0, failed = 0, skipped = 0 }, Root)
end

function Root:summary()
	local total = self.passed + self.failed + self.skipped
	io.write(string.format(
		"\n%d passed  %d failed  %d skipped  (%d total)\n",
		self.passed, self.failed, self.skipped, total))
	return self.failed == 0
end

function Root:exit()
	if not self:summary() then os.exit(1) end
end

M.Root = Root

--
-- Convenience constructors
--

function M.suite(name)
	return Suite.new(name, nil)
end

function M.root()
	local r = Root.new()
	return r, function(name) return Suite.new(name, r) end
end

return M
