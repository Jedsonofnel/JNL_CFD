-- [nfnl] fnl/nabla/util.fnl
local function number_3f(val)
  return (type(val) == "number")
end
local function numbers_3f(...)
  local res = true
  for _, val in ipairs({...}) do
    if not res then break end
    res = number_3f(val)
  end
  return res
end
local function positive_integer_3f(val)
  return (number_3f(val) and (0 < val) and (val == math.floor(val)))
end
return {["number?"] = number_3f, ["numbers?"] = numbers_3f, ["positive-integer?"] = positive_integer_3f}
