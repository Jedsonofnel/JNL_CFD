-- [nfnl] fnl/nabla/core/validation.fnl
local function assert_typeof(val, t, label)
  if (type(val) ~= t) then
    return error(string.format("%s: expected %s, got %s", label, t, type(val)), 3)
  else
    return nil
  end
end
local function assert_number(val, _3flabel)
  if (type(val) ~= "number") then
    return error(string.format("%s: expected number, got %s", (_3flabel or "error"), type(val)))
  else
    return nil
  end
end
local function assert_positive_integer(val, _3flabel)
  if ((type(val) ~= "number") or (val < 0) or (math.floor(val) ~= val)) then
    return error(string.format("%s: expected positive integer, got %s (%s)", (_3flabel or "error"), val, type(val)))
  else
    return nil
  end
end
local function assert_identifier(s, label)
  assert_typeof(s, "string", label)
  if s:match("^__") then
    error(string.format("%s: names starting with __ are reserved: %s", label, s), 3)
  else
  end
  if not s:match("^[%a_][%a%d_]*$") then
    return error(string.format("%s: not a valid identifier: %s", label, s), 3)
  else
    return nil
  end
end
local function assert_oneof(val, options, label)
  local found
  do
    local found0 = false
    for _, opt in ipairs(options) do
      if found0 then break end
      found0 = (val == opt)
    end
    found = found0
  end
  if not found then
    return error(string.format("%s: expected one of [%s], got '%s'", label, table.concat(options, "|"), val), 3)
  else
    return nil
  end
end
return {["assert-typeof"] = assert_typeof, ["assert-number"] = assert_number, ["assert-positive-integer"] = assert_positive_integer, ["assert-identifier"] = assert_identifier, ["assert-oneof"] = assert_oneof}
