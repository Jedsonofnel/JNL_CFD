-- lua/jnl/doc/scanner.lua - source documentation scanner for JNL Lua modules
-- <jed@nelson.ac> // 2026-06-11

--- Scan Lua source files into a linked documentation model.
---
--- This module deliberately recognises a small LuaLS-style annotation subset
--- and predictable JNL declaration forms. It never executes scanned modules.
---@private
local M = {}

local BUILTIN_TYPES = {
	["any"] = true,
	["boolean"] = true,
	["function"] = true,
	["integer"] = true,
	["lightuserdata"] = true,
	["nil"] = true,
	["none"] = true,
	["number"] = true,
	["string"] = true,
	["table"] = true,
	["thread"] = true,
	["userdata"] = true,
	["unknown"] = true,
	["void"] = true,
	["self"] = true,
	["true"] = true,
	["false"] = true,
}

local TYPE_KEYWORDS = {
	["fun"] = true,
	["return"] = true,
}

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

local function ends_with(s, suffix)
	return suffix == "" or s:sub(- #suffix) == suffix
end

local function shallow_copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

local function append(dst, src)
	for _, value in ipairs(src or {}) do
		dst[#dst + 1] = value
	end
end

local function split_csv(s)
	local out = {}
	local start = 1
	local depth_angle = 0
	local depth_paren = 0
	local depth_brace = 0
	local depth_bracket = 0
	local quote = nil
	local escaped = false

	for i = 1, #s do
		local ch = s:sub(i, i)
		if quote then
			if escaped then
				escaped = false
			elseif ch == "\\" then
				escaped = true
			elseif ch == quote then
				quote = nil
			end
		else
			if ch == '"' or ch == "'" then
				quote = ch
			elseif ch == "<" then
				depth_angle = depth_angle + 1
			elseif ch == ">" and depth_angle > 0 then
				depth_angle = depth_angle - 1
			elseif ch == "(" then
				depth_paren = depth_paren + 1
			elseif ch == ")" and depth_paren > 0 then
				depth_paren = depth_paren - 1
			elseif ch == "{" then
				depth_brace = depth_brace + 1
			elseif ch == "}" and depth_brace > 0 then
				depth_brace = depth_brace - 1
			elseif ch == "[" then
				depth_bracket = depth_bracket + 1
			elseif ch == "]" and depth_bracket > 0 then
				depth_bracket = depth_bracket - 1
			elseif ch == ","
				and depth_angle == 0
				and depth_paren == 0
				and depth_brace == 0
				and depth_bracket == 0
			then
				local part = trim(s:sub(start, i - 1))
				if part ~= "" then out[#out + 1] = part end
				start = i + 1
			end
		end
	end

	local part = trim(s:sub(start))
	if part ~= "" then out[#out + 1] = part end
	return out
end

local function shell_quote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function normalize_path(path)
	return (path:gsub("//+", "/"))
end

local function read_file(path)
	local file, err = io.open(path, "rb")
	if not file then return nil, err end
	local source = file:read("*a")
	file:close()
	return source
end

local function source_lines(source)
	local lines = {}
	source = source:gsub("\r\n", "\n"):gsub("\r", "\n")
	if source:sub(-1) ~= "\n" then source = source .. "\n" end
	for line in source:gmatch("(.-)\n") do lines[#lines + 1] = line end
	return lines
end

local function add_diagnostic(index, severity, code, message, context)
	local d = shallow_copy(context)
	d.severity = severity
	d.code = code
	d.message = message
	index.diagnostics[#index.diagnostics + 1] = d
	return d
end

local function describe_location(module_name, path, line)
	return {
		module = module_name,
		path = path,
		line = line,
	}
end

local function parse_named_type_and_doc(rest)
	rest = trim(rest)
	if rest == "" then return nil, "" end

	local depth_angle = 0
	local depth_paren = 0
	local depth_brace = 0
	local depth_bracket = 0
	local quote = nil
	local escaped = false
	local previous_nonspace = nil

	for i = 1, #rest do
		local ch = rest:sub(i, i)
		if quote then
			if escaped then
				escaped = false
			elseif ch == "\\" then
				escaped = true
			elseif ch == quote then
				quote = nil
			end
		else
			if ch == '"' or ch == "'" then
				quote = ch
			elseif ch == "<" then
				depth_angle = depth_angle + 1
			elseif ch == ">" and depth_angle > 0 then
				depth_angle = depth_angle - 1
			elseif ch == "(" then
				depth_paren = depth_paren + 1
			elseif ch == ")" and depth_paren > 0 then
				depth_paren = depth_paren - 1
			elseif ch == "{" then
				depth_brace = depth_brace + 1
			elseif ch == "}" and depth_brace > 0 then
				depth_brace = depth_brace - 1
			elseif ch == "[" then
				depth_bracket = depth_bracket + 1
			elseif ch == "]" and depth_bracket > 0 then
				depth_bracket = depth_bracket - 1
			elseif ch:match("%s")
				and depth_angle == 0
				and depth_paren == 0
				and depth_brace == 0
				and depth_bracket == 0
			then
				local next_nonspace = rest:match("^%s*(.)", i)
				local continues = next_nonspace == "|"
					or next_nonspace == "&"
					or previous_nonspace == "|"
					or previous_nonspace == "&"
					or previous_nonspace == ":"
					or previous_nonspace == ","
				if not continues then
					local type_expr = trim(rest:sub(1, i - 1))
					local description = trim(rest:sub(i + 1))
					if description:sub(1, 1) == "#" then
						description = trim(description:sub(2))
					end
					return type_expr, description
				end
			end
		end
		if not ch:match("%s") then previous_nonspace = ch end
	end

	return rest, ""
end

local function parse_param(rest)
	local name, tail = rest:match("^(%S+)%s+(.+)$")
	if not name then return nil end
	local type_expr, description = parse_named_type_and_doc(tail)
	if not type_expr then return nil end
	local optional = name:sub(-1) == "?"
	if optional then name = name:sub(1, -2) end
	return {
		name = name,
		type = type_expr,
		doc = description,
		optional = optional,
	}
end

local function parse_return(rest)
	local type_expr, description = parse_named_type_and_doc(rest)
	if not type_expr then return nil end
	return {
		type = type_expr,
		doc = description,
	}
end

local function parse_field(rest)
	rest = trim(rest)

	local visibility
	local first, tail = rest:match("^(%S+)%s+(.+)$")

	if first == "public"
		or first == "private"
		or first == "protected"
	then
		visibility = first
		rest = tail
	end

	local name, type_tail = rest:match("^(%S+)%s+(.+)$")
	if not name then return nil end

	local type_expr, description =
		parse_named_type_and_doc(type_tail)

	if not type_expr then return nil end

	local optional = name:sub(-1) == "?"

	if optional then
		name = name:sub(1, -2)
	end

	return {
		name = name,
		type = type_expr,
		doc = description,
		optional = optional,
		visibility = visibility or "public",
	}
end

local function parse_doc_block(raw_lines)
	local doc = {
		description_lines = {},
		params = {},
		returns = {},
		fields = {},
		alias_values = {},
	}

	for _, raw in ipairs(raw_lines) do
		local line = trim(raw)
		local tag, rest = line:match("^@([%w_]+)%s*(.*)$")
		if tag then
			if tag == "class" then
				local name, description = rest:match("^(%S+)%s*(.*)$")
				doc.class = name

				if description and trim(description) ~= "" then
					doc.class_doc = trim(description)
				end
			elseif tag == "alias" then
				local name, type_expr = rest:match("^(%S+)%s*(.*)$")
				doc.alias = name

				if type_expr and trim(type_expr) ~= "" then
					doc.alias_type = trim(type_expr)
				end
			elseif tag == "field" then
				local field = parse_field(rest)
				if field then doc.fields[#doc.fields + 1] = field end
			elseif tag == "type" then
				doc.type = trim(rest)
			elseif tag == "param" then
				local param = parse_param(rest)
				if param then doc.params[#doc.params + 1] = param end
			elseif tag == "return" then
				local ret = parse_return(rest)
				if ret then doc.returns[#doc.returns + 1] = ret end
			elseif tag == "private" then
				doc.private = true
			elseif tag == "public" then
				doc.public = true
			elseif tag == "deprecated" then
				doc.deprecated = trim(rest)
				if doc.deprecated == "" then doc.deprecated = true end
			else
				doc.unknown_tags = doc.unknown_tags or {}
				doc.unknown_tags[#doc.unknown_tags + 1] = {
					name = tag,
					value = trim(rest),
				}
			end
		elseif line:match("^|") then
			local value, description = line:match("^|%s*(.-)%s*#%s*(.*)$")
			if not value then value = trim(line:sub(2)) end
			doc.alias_values[#doc.alias_values + 1] = {
				value = trim(value or ""),
				doc = trim(description or ""),
			}
		else
			doc.description_lines[#doc.description_lines + 1] = raw
		end
	end

	while #doc.description_lines > 0 and trim(doc.description_lines[1]) == "" do
		table.remove(doc.description_lines, 1)
	end
	while #doc.description_lines > 0 and trim(doc.description_lines[#doc.description_lines]) == "" do
		table.remove(doc.description_lines)
	end

	local paragraphs = {}
	local current = {}
	for _, line in ipairs(doc.description_lines) do
		line = trim(line)
		if line == "" then
			if #current > 0 then
				paragraphs[#paragraphs + 1] = table.concat(current, " ")
				current = {}
			end
		else
			current[#current + 1] = line
		end
	end
	if #current > 0 then paragraphs[#paragraphs + 1] = table.concat(current, " ") end
	doc.paragraphs = paragraphs
	doc.description = table.concat(paragraphs, "\n\n")

	return doc
end

local function qualify_type(module_name, name)
	if name:find("%.") then return name end
	return module_name .. "." .. name
end

local function short_name(name)
	return name:match("([%w_]+)$") or name
end

local function make_module(module_name, path)
	return {
		name = module_name,
		path = path,
		doc = "",
		paragraphs = {},
		private = false,
		export_root = nil,
		functions = {},
		function_list = {},
		types = {},
		type_list = {},
		values = {},
		value_list = {},
		locals = {},
	}
end

local function add_type(index, module, type_doc)
	local qualified = qualify_type(module.name, type_doc.name)
	type_doc.qualified_name = qualified
	type_doc.module = module.name
	type_doc.short_name = short_name(type_doc.name)
	type_doc.methods = type_doc.methods or {}
	type_doc.constructors = type_doc.constructors or {}

	if index.types[qualified] then
		add_diagnostic(index, "warning", "duplicate-type",
			"duplicate type definition: " .. qualified,
			describe_location(module.name, module.path, type_doc.line))
		return index.types[qualified]
	end

	index.types[qualified] = type_doc
	module.types[qualified] = type_doc
	module.type_list[#module.type_list + 1] = type_doc
	return type_doc
end

local function add_symbol(index, module, symbol)
	if index.symbols[symbol.qualified_name] then
		add_diagnostic(index, "warning", "duplicate-symbol",
			"duplicate symbol definition: " .. symbol.qualified_name,
			describe_location(module.name, module.path, symbol.line))
		return index.symbols[symbol.qualified_name]
	end

	index.symbols[symbol.qualified_name] = symbol
	module.functions[symbol.qualified_name] = symbol
	module.function_list[#module.function_list + 1] = symbol
	return symbol
end

local function function_decl(line)
	local target, args = line:match("^%s*function%s+([%w_%.:]+)%s*%((.-)%)")
	if target then return target, args, false end

	target, args = line:match("^%s*([%w_%.:]+)%s*=%s*function%s*%((.-)%)")
	if target then return target, args, false end

	local local_name
	local_name, args = line:match("^%s*local%s+function%s+([%w_]+)%s*%((.-)%)")
	if local_name then return local_name, args, true end

	local_name, args = line:match("^%s*local%s+([%w_]+)%s*=%s*function%s*%((.-)%)")
	if local_name then return local_name, args, true end

	return nil
end

local function table_decl(line)
	local name = line:match("^%s*local%s+([%w_]+)%s*=%s*{%s*}%s*[;,]?%s*$")
	if name then return name, true end
	name = line:match("^%s*([%w_%.]+)%s*=%s*{%s*}%s*[;,]?%s*$")
	if name then return name, false end
	return nil
end

local function value_decl(line)
	local target = line:match("^%s*([%w_%.]+)%s*=%s*[^=].*$")
	if target then return target, false end
	target = line:match("^%s*local%s+([%w_]+)%s*=%s*.+$")
	if target then return target, true end
	return nil
end

local function parse_args(args)
	local out = {}
	for _, arg in ipairs(split_csv(args or "")) do
		arg = trim(arg)
		if arg ~= "" then out[#out + 1] = arg end
	end
	return out
end

local function split_target(target)
	local owner, sep, name = target:match("^(.-)([%.:])([%w_]+)$")
	if owner then return owner, sep, name end
	return nil, nil, target
end

local function attach_params(index, module, symbol, lua_params, annotations)
	local by_name = {}
	for _, param in ipairs(annotations or {}) do by_name[param.name] = param end

	for _, name in ipairs(lua_params) do
		local annotated = by_name[name]
		symbol.params[#symbol.params + 1] = {
			name = name,
			type = annotated and annotated.type or nil,
			doc = annotated and annotated.doc or "",
			optional = annotated and annotated.optional or false,
		}
		by_name[name] = nil
	end

	for name, param in pairs(by_name) do
		symbol.params[#symbol.params + 1] = shallow_copy(param)
		add_diagnostic(index, "warning", "unknown-parameter",
			string.format("%s documents parameter '%s' not present in its declaration",
				symbol.qualified_name, name),
			describe_location(module.name, module.path, symbol.line))
	end
end

local function target_is_exported(target, export_root)
	if not export_root then return false end
	return target == export_root or starts_with(target, export_root .. ".")
end

local function finalize_function(index, module, candidate, class_vars)
	local owner, sep, name = split_target(candidate.target)
	local exported = target_is_exported(candidate.target, module.export_root)
	local class_type = owner and class_vars[owner] or nil
	local doc = candidate.doc or parse_doc_block({})
	local private = doc.private
		or (name and starts_with(name, "_"))
		or (candidate.is_local and not doc.public)

	local kind
	local qualified_name
	local display_name
	local receiver

	if class_type then
		kind = "method"
		receiver = class_type.qualified_name
		qualified_name = receiver .. ":" .. name
		display_name = class_type.short_name .. ":" .. name
		private = doc.private or (name and starts_with(name, "_"))
	elseif exported then
		kind = "function"

		if candidate.target == module.export_root then
			qualified_name = module.name
			display_name = module.name
		else
			local relative = candidate.target:sub(
				#module.export_root + 2
			)

			qualified_name = module.name
				.. "."
				.. relative:gsub(":", ".")

			display_name = module.name
				.. "."
				.. relative
		end

		private = doc.private
			or starts_with(name or "", "_")
	elseif doc.public then
		kind = "function"
		qualified_name = module.name .. "." .. candidate.target:gsub(":", ".")
		display_name = qualified_name
		private = false
	else
		kind = "local-function"
		qualified_name = module.name .. ".<local>." .. candidate.target:gsub(":", ".")
		display_name = candidate.target
		private = true
	end

	local symbol = {
		name = name,
		target = candidate.target,
		qualified_name = qualified_name,
		display_name = display_name,
		module = module.name,
		path = module.path,
		line = candidate.line,
		kind = kind,
		receiver = receiver,
		colon = sep == ":",
		private = private,
		deprecated = doc.deprecated,
		doc = doc.description or "",
		paragraphs = doc.paragraphs or {},
		params = {},
		returns = {},
	}

	attach_params(index, module, symbol, candidate.args, doc.params)
	for _, ret in ipairs(doc.returns or {}) do
		symbol.returns[#symbol.returns + 1] = shallow_copy(ret)
	end

	if not private then
		add_symbol(index, module, symbol)
		if class_type then class_type.methods[#class_type.methods + 1] = symbol end
	end
	module.locals[qualified_name] = symbol
	return symbol
end

local function finalize_value(index, module, candidate)
	local doc = candidate.doc
	if not doc or not doc.type then return end
	if candidate.is_local and not doc.public then return end
	if not target_is_exported(candidate.target, module.export_root) and not doc.public then return end

	local relative = candidate.target
	if module.export_root and starts_with(relative, module.export_root .. ".") then
		relative = relative:sub(#module.export_root + 2)
	end

	local value = {
		name = relative,
		qualified_name = module.name .. "." .. relative,
		module = module.name,
		path = module.path,
		line = candidate.line,
		type = doc.type,
		doc = doc.description or "",
		deprecated = doc.deprecated,
		private = doc.private or starts_with(short_name(relative), "_"),
	}
	if value.private then return end
	module.values[value.qualified_name] = value
	module.value_list[#module.value_list + 1] = value
	index.symbols[value.qualified_name] = value
end

local function finalize_short_type_index(index)
	index.short_types = {}
	for qualified, type_doc in pairs(index.types) do
		local short = type_doc.short_name
		local existing = index.short_types[short]
		if not existing then
			index.short_types[short] = qualified
		elseif type(existing) == "string" then
			index.short_types[short] = { existing, qualified }
		else
			existing[#existing + 1] = qualified
		end
	end
end

local function extract_type_names(type_expr)
	local names = {}
	local seen = {}
	if not type_expr or type_expr == "" then return names end

	local scrubbed = type_expr
		:gsub('".-"', " ")
		:gsub("'.-'", " ")

	for token in scrubbed:gmatch("[%a_][%w_%.]*") do
		if not BUILTIN_TYPES[token]
			and not TYPE_KEYWORDS[token]
			and not token:match("^%d")
			and not seen[token]
		then
			seen[token] = true
			names[#names + 1] = token
		end
	end
	return names
end

local function resolve_type_name(index, module_name, name)
	if BUILTIN_TYPES[name] or TYPE_KEYWORDS[name] then return nil, "builtin" end
	if index.types[name] then return name end

	local local_name = module_name .. "." .. name
	if index.types[local_name] then return local_name end

	local match = index.short_types[name]
	if type(match) == "string" then return match end
	if type(match) == "table" then return nil, "ambiguous", match end
	return nil, "unresolved"
end

local function collect_type_refs(index, owner, type_expr)
	local refs = {}
	for _, name in ipairs(extract_type_names(type_expr)) do
		local resolved, reason, matches = resolve_type_name(index, owner.module, name)
		refs[#refs + 1] = {
			name = name,
			resolved = resolved,
			reason = reason,
			matches = matches,
		}
	end
	return refs
end

local function link_index(index)
	finalize_short_type_index(index)
	index.references = {}

	local function link_owner(owner, type_expr, field)
		for _, ref in ipairs(collect_type_refs(index, owner, type_expr)) do
			local item = {
				owner = owner.qualified_name,
				owner_kind = owner.kind or "type",
				module = owner.module,
				path = owner.path,
				line = owner.line,
				field = field,
				type_expr = type_expr,
				name = ref.name,
				resolved = ref.resolved,
				reason = ref.reason,
				matches = ref.matches,
			}
			index.references[#index.references + 1] = item
			if ref.reason == "unresolved" then
				add_diagnostic(index, "warning", "unresolved-type",
					string.format("%s references unresolved type '%s'", owner.qualified_name, ref.name),
					describe_location(owner.module, owner.path, owner.line))
			elseif ref.reason == "ambiguous" then
				add_diagnostic(index, "warning", "ambiguous-type",
					string.format("%s references ambiguous type '%s': %s",
						owner.qualified_name, ref.name, table.concat(ref.matches, ", ")),
					describe_location(owner.module, owner.path, owner.line))
			end
		end
	end

	for _, module in pairs(index.modules) do
		for _, symbol in ipairs(module.function_list) do
			for _, param in ipairs(symbol.params) do
				link_owner(symbol, param.type, "param:" .. param.name)
			end
			for i, ret in ipairs(symbol.returns) do
				link_owner(symbol, ret.type, "return:" .. i)
				if symbol.kind == "function" then
					for _, ref in ipairs(collect_type_refs(index, symbol, ret.type)) do
						local type_doc = ref.resolved and index.types[ref.resolved] or nil
						if type_doc and type_doc.kind == "class" then
							type_doc.constructors[#type_doc.constructors + 1] = symbol
						end
					end
				end
			end
		end
		for _, value in ipairs(module.value_list) do
			link_owner(value, value.type, "value")
		end
		for _, type_doc in ipairs(module.type_list) do
			if type_doc.alias_type then link_owner(type_doc, type_doc.alias_type, "alias") end
			for _, alias_value in ipairs(type_doc.alias_values or {}) do
				link_owner(type_doc, alias_value.value, "alias-value")
			end
			for _, field in ipairs(type_doc.fields or {}) do
				link_owner(type_doc, field.type, "field:" .. field.name)
			end
		end
	end
end

local function scan_source(index, module_name, path, source)
	local module = make_module(module_name, path)
	index.modules[module_name] = module

	local lines = source_lines(source)
	local pending = nil
	local candidates = {}
	local values = {}
	local table_docs = {}
	local class_vars = {}

	local function consume_pending()
		local doc = pending and parse_doc_block(pending.lines) or nil
		pending = nil
		return doc
	end

	local function flush_standalone()
		if not pending then return end

		local doc = parse_doc_block(pending.lines)

		if doc.alias then
			local type_doc = {
				name = doc.alias,
				kind = "alias",
				line = pending.line,
				path = path,
				doc = doc.description or "",
				paragraphs = doc.paragraphs or {},
				alias_type = doc.alias_type,
				alias_values = doc.alias_values or {},
				fields = {},
				methods = {},
				constructors = {},
				private = doc.private,
				deprecated = doc.deprecated,
			}

			if not type_doc.private then
				add_type(index, module, type_doc)
			end
		end

		pending = nil
	end

	for line_no, line in ipairs(lines) do
		local doc_text = line:match("^%s*%-%-%-(.*)$")
		if doc_text ~= nil then
			if not pending then pending = { line = line_no, lines = {} } end
			pending.lines[#pending.lines + 1] = doc_text
		else
			local target, args, is_local = function_decl(line)
			if target then
				local doc = consume_pending()
				candidates[#candidates + 1] = {
					target = target,
					args = parse_args(args),
					is_local = is_local,
					line = line_no,
					doc = doc,
				}
			else
				local table_name, table_local = table_decl(line)
				if table_name then
					local doc = consume_pending()
					table_docs[table_name] = doc

					if doc and doc.class then
						local type_doc = {
							name = doc.class,
							kind = "class",
							line = line_no,
							path = path,
							doc = doc.class_doc or doc.description or "",
							paragraphs = doc.paragraphs or {},
							fields = doc.fields or {},
							methods = {},
							constructors = {},
							alias_values = {},
							private = doc.private,
							deprecated = doc.deprecated,
							lua_name = table_name,
						}
						if not type_doc.private then
							local added = add_type(index, module, type_doc)
							class_vars[table_name] = added
						end
					elseif table_local then
						module.locals[table_name] = { kind = "table", line = line_no }
					end
				else
					local value_name, value_local = value_decl(line)
					if value_name and pending then
						local doc = consume_pending()
						if doc and doc.alias then
							local type_doc = {
								name = doc.alias,
								kind = "alias",
								line = line_no,
								path = path,
								doc = doc.description or "",
								paragraphs = doc.paragraphs or {},
								alias_type = doc.alias_type,
								alias_values = doc.alias_values or {},
								fields = {},
								methods = {},
								constructors = {},
								private = doc.private,
								deprecated = doc.deprecated,
							}
							if not type_doc.private then add_type(index, module, type_doc) end
						else
							values[#values + 1] = {
								target = value_name,
								is_local = value_local,
								line = line_no,
								doc = doc,
							}
						end
					elseif trim(line) == "" then
						flush_standalone()
					elseif pending then
						flush_standalone()
					end
				end
			end
		end
	end
	flush_standalone()

	for i = #lines, 1, -1 do
		local root = lines[i]:match("^%s*return%s+([%w_]+)%s*$")
		if root then
			module.export_root = root
			break
		end
	end

	if module.export_root and table_docs[module.export_root] then
		local doc = table_docs[module.export_root]
		module.doc = doc.description or ""
		module.paragraphs = doc.paragraphs or {}
		module.private = doc.private or false
	end

	if not module.export_root then
		add_diagnostic(index, "warning", "missing-export-root",
			"could not infer returned module table",
			describe_location(module_name, path, nil))
	end

	for _, candidate in ipairs(candidates) do
		finalize_function(index, module, candidate, class_vars)
	end
	for _, candidate in ipairs(values) do
		finalize_value(index, module, candidate)
	end

	return module
end

--- Resolve a Lua module name to a source file through package.path.
---@param module_name string Dotted Lua module name.
---@param package_path? string Search path; defaults to package.path.
---@return string? path
---@return string? error
function M.resolve_module(module_name, package_path)
	if type(module_name) ~= "string" or module_name == "" then
		return nil, "module name must be a non-empty string"
	end

	package_path = package_path or package.path
	if package.searchpath then
		local path, err = package.searchpath(module_name, package_path)
		if path then return path end
		return nil, err
	end

	local module_path = module_name:gsub("%.", "/")
	local errors = {}
	for template in package_path:gmatch("[^;]+") do
		local candidate = template:gsub("%?", module_path)
		local file = io.open(candidate, "rb")
		if file then
			file:close()
			return candidate
		end
		errors[#errors + 1] = "no file '" .. candidate .. "'"
	end
	return nil, table.concat(errors, "\n")
end

local function path_roots(package_path)
	local roots = {}
	local seen = {}
	for template in package_path:gmatch("[^;]+") do
		local before = template:match("^(.-)%?")
		if before then
			before = normalize_path(before)
			if before ~= "" and not seen[before] then
				seen[before] = true
				roots[#roots + 1] = before
			end
		end
	end
	return roots
end

local function default_list_files(dir)
	local pipe = io.popen("find " .. shell_quote(dir) .. " -type f -name '*.lua' -print 2>/dev/null")
	if not pipe then return {}, "could not launch find" end
	local files = {}
	for line in pipe:lines() do files[#files + 1] = normalize_path(line) end
	pipe:close()
	table.sort(files)
	return files
end

local function module_name_from_path(root, path)
	root = normalize_path(root)
	path = normalize_path(path)
	if not starts_with(path, root) then return nil end
	local relative = path:sub(#root + 1)
	if starts_with(relative, "/") then relative = relative:sub(2) end
	if not ends_with(relative, ".lua") then return nil end
	relative = relative:sub(1, -5)
	if ends_with(relative, "/init") then relative = relative:sub(1, -6) end
	return relative:gsub("/", ".")
end

--- Discover Lua modules below a dotted package prefix.
---
--- The default implementation uses the system `find` command. Supply
--- `opts.list_files(dir)` to replace filesystem enumeration.
---@param package_name string Dotted package prefix such as `jnl.fvm`.
---@param opts? table Discovery options.
---@return string[] modules
---@return table[] diagnostics
function M.discover_package(package_name, opts)
	opts = opts or {}
	local package_path = opts.package_path or package.path
	local list_files = opts.list_files or default_list_files
	local package_rel = package_name:gsub("%.", "/")
	local modules = {}
	local seen = {}
	local diagnostics = {}

	for _, root in ipairs(path_roots(package_path)) do
		local dir = normalize_path(root .. package_rel)
		local files, err = list_files(dir)
		if err then
			diagnostics[#diagnostics + 1] = {
				severity = "warning",
				code = "package-discovery-failed",
				message = tostring(err),
				path = dir,
			}
		end
		for _, path in ipairs(files or {}) do
			local module_name = module_name_from_path(root, path)
			if module_name
				and (module_name == package_name or starts_with(module_name, package_name .. "."))
				and not seen[module_name]
			then
				seen[module_name] = true
				modules[#modules + 1] = module_name
			end
		end
	end

	table.sort(modules)
	return modules, diagnostics
end

--- Extract named type references from a lightweight LuaLS-style type expression.
---@param type_expr string Type expression such as `table<string, Spec>`.
---@return string[] names
function M.type_names(type_expr)
	return extract_type_names(type_expr)
end

--- Scan Lua source modules into a documentation index.
---
--- Modules are resolved without executing them. Pass explicit `modules`, package
--- prefixes in `packages`, or both. Package discovery may be customised with
--- `list_files`; source loading may be customised with `read_file`.
---@param opts table Scanner options.
---@return table index Raw documentation index.
function M.scan(opts)
	opts = opts or {}
	local index = {
		modules = {},
		types = {},
		symbols = {},
		references = {},
		diagnostics = {},
		package_path = opts.package_path or package.path,
	}

	local names = {}
	local seen = {}
	local function add_name(name)
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end

	for _, name in ipairs(opts.modules or {}) do add_name(name) end
	for _, package_name in ipairs(opts.packages or {}) do
		local discovered, diagnostics = M.discover_package(package_name, {
			package_path = index.package_path,
			list_files = opts.list_files,
		})
		for _, name in ipairs(discovered) do add_name(name) end
		append(index.diagnostics, diagnostics)
	end
	table.sort(names)

	---@type fun(path: string): string?, string?
	local read_source = opts.read_file or read_file

	for _, module_name in ipairs(names) do
		local path, resolve_err = M.resolve_module(module_name, index.package_path)

		if not path then
			add_diagnostic(index, "error", "module-not-found",
				"could not resolve module '" .. module_name .. "': " .. tostring(resolve_err),
				{ module = module_name })
		else
			local source, read_err = read_source(path)

			if not source then
				add_diagnostic(index, "error", "source-read-failed",
					"could not read module '" .. module_name .. "': " .. tostring(read_err),
					{ module = module_name, path = path })
			else
				scan_source(index, module_name, path, source)
			end
		end
	end

	link_index(index)
	return index
end

return M
