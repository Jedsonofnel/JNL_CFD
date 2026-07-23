-- [nfnl] fnl/nabla/fvm/chasm-original/block.fnl
local _local_1_ = require("nabla.fvm.chasm.program")
local program_get_var = _local_1_["program-get-var"]
local Block = {}
Block.__index = Block
local function new_block(prog, name, iters, depth)
  assert(prog, "new-block: prog is nil, required")
  return setmetatable({prog = prog, name = name, iters = iters, depth = (depth or 1), instructions = {}, convergence = {}}, Block)
end
local function add_inst_21(_2_, inst)
  local instructions = _2_.instructions
  local block = _2_
  table.insert(instructions, inst)
  return block
end
local function get_var(_3_, v)
  local prog = _3_.prog
  return program_get_var(prog, v)
end
local function until_all_21(_4_, ...)
  local convergence = _4_.convergence
  local preds = {...}
  assert((#preds ~= 0), "block-until-all! expects at least one predicate")
  return table.insert(convergence, {kind = "all", preds = preds})
end
local function until_any_21(_5_, ...)
  local convergence = _5_.convergence
  local preds = {...}
  assert((#preds ~= 0), "block-until-any! expects at least one predicate")
  return table.insert(convergence, {kind = "any", preds = preds})
end
Block["emit!"] = function(block, op_name, ...)
  local isa = block.prog.ISA
  local entry = (isa[op_name] or error(("unknown ISA op " .. op_name)))
  local inst = entry.build(block, ...)
  inst.op = op_name
  return add_inst_21(block, inst)
end
local function listing_str(_block, _indent_level)
  return error("this is a forward declaration")
end
local function inst_line(prog, indent_level, inst)
  if inst.instructions then
    return ("\n" .. listing_str(inst, (indent_level + 1)))
  else
    local indent = string.rep("  ", indent_level)
    return string.format("%s%s", indent, prog.ISA[inst.op]("str", inst))
  end
end
local function listing_str0(block, indent_level)
  local indent_level0 = (indent_level or 0)
  local indent = string.rep("  ", indent_level0)
  local header = (indent .. ">>" .. block.name)
  local body
  do
    local tbl_26_ = {}
    local i_27_ = 0
    for _, inst in ipairs(block.instructions) do
      local val_28_ = inst_line(block.prog, indent_level0, inst)
      if (nil ~= val_28_) then
        i_27_ = (i_27_ + 1)
        tbl_26_[i_27_] = val_28_
      else
      end
    end
    body = tbl_26_
  end
  local footer = (indent .. "<<")
  return table.concat({header, table.concat(body, "\n"), footer}, "\n")
end
Block.__tostring = function(_8_)
  local name = _8_.name
  local instructions = _8_.instructions
  local depth = _8_.depth
  return string.format("#<block:%s instrs:%d depth:%s>", name, #instructions, depth)
end
return {new = new_block, ["listing-str"] = listing_str0, ["get-var"] = get_var, ["add-inst!"] = add_inst_21}
