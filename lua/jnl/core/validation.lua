-- validation.lua - validation library for various bits
-- <jed@nelson.ac> // 2026-05-11

local V = {}

function V.typeof(val, t, label)
	if type(val) ~= t then
		error(string.format("%s: expected %s, got %s", label, t, type(val)), 3)
	end
end

function V.oneof(val, options, label)
	for _, v in ipairs(options) do
		if val == v then return end
	end
	error(string.format("%s: expected one of [%s], got '%s'",
		label, table.concat(options, "|"), tostring(val)), 3)
end

function V.nonempty(t, label)
	V.typeof(t, "table", label)
	if #t == 0 then
		error(label .. ": must be a non-empty list", 3)
	end
end

function V.identifier(s, label)
	V.typeof(s, "string", label)
	if s:match("^__") then
		error(label .. ": names starting with __ are reserved: " .. s, 3)
	end
	if not s:match("^[%a_][%a%d_]*$") then
		error(label .. ": not a valid identifier: " .. s, 3)
	end
end

function V.keys(t)
	local ks = {}
	for k in pairs(t) do ks[#ks + 1] = k end
	return ks
end

-- Case-sensitive membership test
function V.in_set(set, name, ctx)
	if set[name] then
		return name
	end
	local keys = V.keys(set)
	table.sort(keys) -- deterministic error messages
	error(string.format("%s: '%s' is not valid, expected one of: %s",
		ctx or "value", name, table.concat(keys, ", ")), 2)
end

-- Case-insensitive membership test, always returns UPPERNAME
function V.in_enum(set, name, ctx)
	V.typeof(name, "string", ctx or "enum value")
	local upper = string.upper(name)
	if set[upper] then
		return upper
	end
	local keys = V.keys(set)
	table.sort(keys)
	error(string.format("%s: '%s' is not valid, expected one of: %s",
		ctx or "value", name, table.concat(keys, ", ")), 2)
end

return V
