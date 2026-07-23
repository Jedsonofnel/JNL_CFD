-- [nfnl] fnl/nabla/core/util.fnl
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
local function string_3f(val)
  return (type(val) == "string")
end
local function concat_all(key, results)
  local out = {}
  for _, r in ipairs(results) do
    local keyvals = r[key]
    if keyvals then
      for _0, item in ipairs(keyvals) do
        table.insert(out, item)
      end
    else
    end
  end
  return out
end
--[[ (let [results [{:key [1 2 3]} {:key [4 5 6]} {:key [7 8 10]}]\] (concat-all "key" results)) ]]
--[[ (let [results-missing-key [{:key [1 2 3]} {:bad-key [4 5 6]}]\] (concat-all "key" results-missing-key)) ]]
local function concat_lists_21(l1, l2)
  local tbl_24_ = l1
  for _, val in ipairs(l2) do
    local val_25_ = val
    table.insert(tbl_24_, val_25_)
  end
  return tbl_24_
end
--[[ (let [one-list [1 2 3 4] two-list [5 6 7 8]\] (concat-lists! one-list two-list)) ]]
return {["number?"] = number_3f, ["numbers?"] = numbers_3f, ["positive-integer?"] = positive_integer_3f, ["string?"] = string_3f, ["concat-all"] = concat_all, ["concat-lists!"] = concat_lists_21}
