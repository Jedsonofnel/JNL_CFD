-- [nfnl] lua/nabla/core/validation.fnl
local function typeof(val, t, label)
  if (type(val) ~= t) then
    return error(string.format("%s: expected %s, got %s", label, t, type(val)), 3)
  else
    return nil
  end
end
local function identifier(s, label)
  typeof(s, "string", label)
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
local function oneof(val, options, label)
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
return {typeof = typeof, identifier = identifier, oneof = oneof}
