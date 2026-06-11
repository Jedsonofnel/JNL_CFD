-- lua/jnl/doc/init.lua - public documentation index and renderer for JNL
-- <jed@nelson.ac> // 2026-06-11

local Scanner = require("jnl.doc.scanner")

---Build, query, audit, and render source-derived JNL API documentation.
local M = {}

---A linked documentation index returned by `doc.scan`.
---@class DocIndex
---@field raw table Raw index returned by `jnl.doc.scanner.scan`.
local Index = {}
Index.__index = Index

local function starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

local function shallow_copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

local function sorted_copy(values, key)
	local out = {}
	for _, value in ipairs(values or {}) do out[#out + 1] = value end
	table.sort(out, function(a, b)
		local av = key and a[key] or a
		local bv = key and b[key] or b
		return tostring(av) < tostring(bv)
	end)
	return out
end

local function short_name(name)
	return name:match("([%w_]+)$") or name
end

local function suffix_match(name, suffix)
	return name == suffix or name:sub(- #suffix - 1) == "." .. suffix
end

local function module_is_excluded(name, opts)
	opts = opts or {}

	for _, excluded in ipairs(opts.exclude_modules or {}) do
		if name == excluded
			or starts_with(name, excluded .. ".")
		then
			return true
		end
	end

	return false
end

local function module_is_visible(module, opts)
	opts = opts or {}

	if module.private and not opts.include_private then
		return false
	end

	return not module_is_excluded(module.name, opts)
end

local function constructor_is_visible(index, constructor, opts)
	local module = index.raw.modules[constructor.module]

	return module
		and module_is_visible(module, opts)
end

local function module_has_content(module)
	if module.doc ~= "" then return true end
	if #(module.value_list or {}) > 0 then return true end

	for _, symbol in ipairs(module.function_list or {}) do
		if symbol.kind ~= "method" then
			return true
		end
	end

	return false
end

local function new_printer(opts)
	local Printer = require("jnl.repl.printer")
	return Printer.new({
		width = opts.width or 72,
		out = opts.out,
	})
end

local function resolve_module(index, name)
	if index.raw.modules[name] then return index.raw.modules[name] end
	local matches = {}
	for module_name, module in pairs(index.raw.modules) do
		if suffix_match(module_name, name) then matches[#matches + 1] = module end
	end
	table.sort(matches, function(a, b) return a.name < b.name end)
	if #matches == 1 then return matches[1] end
	if #matches == 0 then return nil, "unknown documented module: " .. tostring(name) end
	local names = {}
	for _, module in ipairs(matches) do names[#names + 1] = module.name end
	return nil, "ambiguous module '" .. tostring(name) .. "': " .. table.concat(names, ", ")
end

local function resolve_type(index, name, module_name)
	if index.raw.types[name] then return index.raw.types[name] end
	if module_name and index.raw.types[module_name .. "." .. name] then
		return index.raw.types[module_name .. "." .. name]
	end
	local match = index.raw.short_types and index.raw.short_types[name]
	if type(match) == "string" then return index.raw.types[match] end
	if type(match) == "table" then
		return nil, "ambiguous type '" .. name .. "': " .. table.concat(match, ", ")
	end
	return nil, "unknown documented type: " .. tostring(name)
end

local function references_for(index, owner_name)
	local refs = {}
	for _, ref in ipairs(index.raw.references or {}) do
		if ref.owner == owner_name and ref.resolved then refs[#refs + 1] = ref.resolved end
	end
	return refs
end

local function add_type_closure(index, qualified, selected, recurse)
	if not qualified or selected[qualified] then return end
	local type_doc = index.raw.types[qualified]
	if not type_doc then return end
	selected[qualified] = type_doc
	if not recurse then return end
	for _, referenced in ipairs(references_for(index, qualified)) do
		add_type_closure(index, referenced, selected, true)
	end
	for _, method in ipairs(type_doc.methods or {}) do
		for _, referenced in ipairs(references_for(index, method.qualified_name)) do
			add_type_closure(index, referenced, selected, true)
		end
	end
end

local function relevant_types(index, modules, mode)
	mode = mode or "closure"

	if mode == "none" then
		return {}
	end

	local selected = {}
	local include_local = mode == "local"
		or mode == "closure"
	local recurse = mode == "closure"

	for _, module in ipairs(modules) do
		if include_local then
			for _, type_doc in ipairs(module.type_list) do
				add_type_closure(
					index,
					type_doc.qualified_name,
					selected,
					recurse
				)
			end
		end

		if mode ~= "local" then
			for _, symbol in ipairs(module.function_list) do
				if symbol.kind ~= "method" then
					for _, referenced in ipairs(
						references_for(index, symbol.qualified_name)
					) do
						add_type_closure(
							index,
							referenced,
							selected,
							recurse
						)
					end
				end
			end

			for _, value in ipairs(module.value_list) do
				for _, referenced in ipairs(
					references_for(index, value.qualified_name)
				) do
					add_type_closure(
						index,
						referenced,
						selected,
						recurse
					)
				end
			end
		end
	end

	local out = {}

	for _, type_doc in pairs(selected) do
		out[#out + 1] = type_doc
	end

	table.sort(out, function(a, b)
		return a.qualified_name < b.qualified_name
	end)

	return out
end

local function function_signature(symbol)
	local args = {}
	for _, param in ipairs(symbol.params or {}) do
		local text = param.name .. (param.optional and "?" or "")
		if param.type and param.type ~= "" then text = text .. ": " .. param.type end
		args[#args + 1] = text
	end

	local name
	if symbol.kind == "method" then
		name = short_name(symbol.receiver) .. ":" .. symbol.name
	else
		name = symbol.qualified_name
	end

	local returns = {}
	for _, ret in ipairs(symbol.returns or {}) do
		if ret.type and ret.type ~= "" then returns[#returns + 1] = ret.type end
	end
	local suffix = #returns > 0 and (" -> " .. table.concat(returns, ", ")) or ""
	return string.format("%s(%s)%s", name, table.concat(args, ", "), suffix)
end

local function dump_paragraphs(p, paragraphs, indent)
	for _, paragraph in ipairs(paragraphs or {}) do
		p:wrap(indent, indent, paragraph)
		p:blank()
	end
end

local function dump_function(p, symbol, indent)
	indent = indent or "   "
	p:wrap(indent, indent, function_signature(symbol))
	if symbol.deprecated then
		local message = symbol.deprecated == true and "deprecated" or ("deprecated: " .. symbol.deprecated)
		p:wrap(indent .. "   ", indent .. "   ", message)
	end
	if symbol.doc and symbol.doc ~= "" then
		p:wrap(indent .. "   ", indent .. "   ", symbol.doc)
	end

	for _, param in ipairs(symbol.params or {}) do
		if param.doc and param.doc ~= "" then
			p:columns(param.name, param.doc, {
				indent = indent .. "   ",
				left_width = 18,
				doc_indent = indent .. "      ",
			})
		end
	end
	for i, ret in ipairs(symbol.returns or {}) do
		if ret.doc and ret.doc ~= "" then
			p:columns("return " .. i, ret.doc, {
				indent = indent .. "   ",
				left_width = 18,
				doc_indent = indent .. "      ",
			})
		end
	end
	p:blank()
end

local function dump_type(index, p, type_doc, opts)
	opts = opts or {}

	local heading = type_doc.qualified_name

	if type_doc.kind == "alias" then
		heading = heading .. " [alias]"
	end

	p:wrap("   ", "   ", heading)

	if type_doc.deprecated then
		local message = type_doc.deprecated == true
			and "deprecated"
			or ("deprecated: " .. type_doc.deprecated)

		p:wrap("      ", "      ", message)
	end

	if type_doc.doc and type_doc.doc ~= "" then
		p:wrap("      ", "      ", type_doc.doc)
	end

	if type_doc.alias_type and type_doc.alias_type ~= "" then
		p:wrap("      ", "      ", "= " .. type_doc.alias_type)
	end

	for _, value in ipairs(type_doc.alias_values or {}) do
		p:columns(value.value, value.doc or "", {
			indent = "      ",
			left_width = 24,
			doc_indent = "         ",
		})
	end

	for _, field in ipairs(type_doc.fields or {}) do
		if field.visibility ~= "private"
			or opts.include_private
		then
			local left = field.name
				.. (field.optional and "?" or "")

			if field.type and field.type ~= "" then
				left = left .. ": " .. field.type
			end

			p:columns(left, field.doc or "", {
				indent = "      ",
				left_width = 28,
				doc_indent = "         ",
			})
		end
	end

	local constructors = {}

	for _, constructor in ipairs(type_doc.constructors or {}) do
		if constructor_is_visible(index, constructor, opts) then
			constructors[#constructors + 1] = constructor
		end
	end

	if #constructors > 0 then
		p:line("      Constructors")

		for _, constructor in ipairs(
			sorted_copy(constructors, "qualified_name")
		) do
			p:wrap(
				"         ",
				"         ",
				function_signature(constructor)
			)
		end
	end

	if #(type_doc.methods or {}) > 0 then
		p:line("      Methods")
		p:blank()

		for _, method in ipairs(
			sorted_copy(type_doc.methods, "qualified_name")
		) do
			dump_function(p, method, "         ")
		end
	end

	p:blank()
end

local function module_functions(module)
	local functions = {}
	for _, symbol in ipairs(module.function_list) do
		if symbol.kind ~= "method" then functions[#functions + 1] = symbol end
	end
	return sorted_copy(functions, "qualified_name")
end

local function module_values(module)
	return sorted_copy(module.value_list, "qualified_name")
end

local function dump_module_body(p, module, opts)
	p:header(module.name, opts.header_level or 2)
	if module.doc and module.doc ~= "" then
		dump_paragraphs(p, module.paragraphs, "   ")
	else
		p:line("   (no module description)")
		p:blank()
	end

	local functions = module_functions(module)
	if #functions > 0 then
		p:line("   Functions")
		p:blank()
		for _, symbol in ipairs(functions) do dump_function(p, symbol, "      ") end
	end

	local values = module_values(module)
	if #values > 0 then
		p:line("   Values")
		p:blank()
		for _, value in ipairs(values) do
			local left = value.qualified_name
			if value.type and value.type ~= "" then left = left .. ": " .. value.type end
			p:columns(left, value.doc or "", {
				indent = "      ",
				left_width = 32,
				doc_indent = "         ",
			})
		end
		p:blank()
	end
end

--- Return documented module names in sorted order.
---@param opts? table Visibility options.
---@return string[] modules
function Index:modules(opts)
	opts = opts or {}

	local names = {}

	for name, module in pairs(self.raw.modules) do
		if module_is_visible(module, opts) then
			names[#names + 1] = name
		end
	end

	table.sort(names)
	return names
end

---Find a documented module by full name or unambiguous suffix.
---@param name string Module name or suffix.
---@return table? module
---@return string? error
function Index:module(name)
	return resolve_module(self, name)
end

--- Return visible documented modules below a package prefix.
---@param prefix string Dotted package prefix.
---@param opts? table Visibility options.
---@return table[] modules
function Index:package(prefix, opts)
	opts = opts or {}

	local modules = {}

	for name, module in pairs(self.raw.modules) do
		if module_is_visible(module, opts)
			and (
				name == prefix
				or starts_with(name, prefix .. ".")
			)
		then
			modules[#modules + 1] = module
		end
	end

	table.sort(modules, function(a, b)
		return a.name < b.name
	end)

	return modules
end

---Find a documented symbol by fully qualified name.
---@param name string Fully qualified symbol name.
---@return table? symbol
function Index:symbol(name)
	return self.raw.symbols[name]
end

---Find a type by qualified name, local module name, or unique short name.
---@param name string Type name.
---@param module_name? string Module used for local type resolution.
---@return table? type_doc
---@return string? error
function Index:type(name, module_name)
	return resolve_type(self, name, module_name)
end

---Search modules, symbols, and types by case-insensitive substring.
---@param query string Search text.
---@return table[] matches
function Index:search(query)
	query = tostring(query or ""):lower()
	local matches = {}
	local function add(kind, name, item)
		local haystack = (name .. " " .. tostring(item.doc or "")):lower()
		if haystack:find(query, 1, true) then
			matches[#matches + 1] = { kind = kind, name = name, item = item }
		end
	end
	for name, module in pairs(self.raw.modules) do add("module", name, module) end
	for name, symbol in pairs(self.raw.symbols) do add(symbol.kind or "symbol", name, symbol) end
	for name, type_doc in pairs(self.raw.types) do add("type", name, type_doc) end
	table.sort(matches, function(a, b)
		if a.kind == b.kind then return a.name < b.name end
		return a.kind < b.kind
	end)
	return matches
end

---Return scanner and audit diagnostics.
---@param opts? table Filtering options, including `severity`.
---@return table[] diagnostics
function Index:diagnostics(opts)
	opts = opts or {}
	local out = {}
	for _, diagnostic in ipairs(self.raw.diagnostics or {}) do
		if not opts.severity or diagnostic.severity == opts.severity then
			out[#out + 1] = shallow_copy(diagnostic)
		end
	end
	return out
end

---Audit documentation completeness and return diagnostics.
---@param opts? table Audit policy.
---@return integer warning_count
---@return table[] diagnostics
function Index:audit(opts)
	opts = opts or {}
	local diagnostics = self:diagnostics()
	local strict = opts.level == "strict"
	local undocumented_public = opts.undocumented_public
	if undocumented_public == nil then undocumented_public = true end
	local missing_param_types = opts.missing_param_types
	if missing_param_types == nil then missing_param_types = strict end
	local missing_return_types = opts.missing_return_types
	if missing_return_types == nil then missing_return_types = false end

	local function add(severity, code, message, item)
		diagnostics[#diagnostics + 1] = {
			severity = severity,
			code = code,
			message = message,
			module = item and item.module,
			path = item and item.path,
			line = item and item.line,
		}
	end

	for _, module in pairs(self.raw.modules) do
		if module_is_visible(module, opts) then
			if undocumented_public
				and (not module.doc or module.doc == "")
			then
				add(
					"warning",
					"undocumented-module",
					module.name .. " has no module description",
					module
				)
			end

			for _, symbol in ipairs(module.function_list) do
				if undocumented_public
					and (not symbol.doc or symbol.doc == "")
				then
					add(
						"warning",
						"undocumented-symbol",
						symbol.qualified_name
						.. " has no description",
						symbol
					)
				end

				if missing_param_types then
					for _, param in ipairs(symbol.params or {}) do
						if param.name ~= "..."
							and (
								not param.type
								or param.type == ""
							)
						then
							add(
								"warning",
								"untyped-parameter",
								symbol.qualified_name
								.. " parameter '"
								.. param.name
								.. "' has no type",
								symbol
							)
						end
					end
				end

				if missing_return_types
					and #symbol.returns == 0
				then
					add(
						"warning",
						"missing-return",
						symbol.qualified_name
						.. " has no return annotation",
						symbol
					)
				end
			end
		end
	end

	local count = 0
	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.severity == "warning" or diagnostic.severity == "error" then count = count + 1 end
		if opts.out then opts.out(diagnostic) end
	end
	return count, diagnostics
end

---Return types relevant to one module according to a traversal policy.
---@param module_name string Module name or suffix.
---@param mode? string One of `none`, `local`, `direct`, or `closure`.
---@return table[] types
---@return string? error
function Index:relevant_types(module_name, mode)
	local module, err = resolve_module(self, module_name)
	if not module then return {}, err end
	return relevant_types(self, { module }, mode or "closure")
end

--- Render the documented module list.
---@param opts? table Rendering and visibility options.
---@return string text
function Index:render_modules(opts)
	opts = opts or {}

	local p = new_printer(opts)

	p:header("Documented modules", 1)

	for _, name in ipairs(self:modules(opts)) do
		local module = self.raw.modules[name]

		p:columns(name, module.doc or "", {
			indent = "  ",
			left_width = opts.left_width or 28,
			doc_indent = "    ",
		})
	end

	return p:string()
end

--- Render one module and its relevant type appendix.
---@param name string Module name or suffix.
---@param opts? table Rendering and visibility options.
---@return string? text
---@return string? error
function Index:render_module(name, opts)
	opts = opts or {}

	local module, err = resolve_module(self, name)

	if not module then
		return nil, err
	end

	if module.private and not opts.include_private then
		return nil, "documented module is private: " .. module.name
	end

	if module_is_excluded(module.name, opts) then
		return nil, "documented module is excluded: " .. module.name
	end

	local p = new_printer(opts)

	p:header(opts.title or "JNL API Reference", 1)
	dump_module_body(p, module, opts)

	local types = relevant_types(
		self,
		{ module },
		opts.types or "closure"
	)

	if #types > 0 then
		p:header("Relevant types", 2)

		for _, type_doc in ipairs(types) do
			dump_type(self, p, type_doc, opts)
		end
	end

	return p:string()
end

--- Render visible modules below a package prefix.
---@param prefix string Dotted package prefix.
---@param opts? table Rendering and visibility options.
---@return string text
function Index:render_package(prefix, opts)
	opts = opts or {}

	local modules = self:package(prefix, opts)
	local p = new_printer(opts)

	p:header(
		opts.title or ("JNL package: " .. prefix),
		1
	)

	if #modules == 0 then
		p:line("No documented modules found.")
		return p:string()
	end

	for _, module in ipairs(modules) do
		if module_has_content(module) then
			dump_module_body(p, module, opts)
		end
	end

	local types = relevant_types(
		self,
		modules,
		opts.types or "direct"
	)

	if #types > 0 then
		p:header("Relevant types", 2)

		for _, type_doc in ipairs(types) do
			dump_type(self, p, type_doc, opts)
		end
	end

	return p:string()
end

--- Render every visible indexed module.
---@param opts? table Rendering and visibility options.
---@return string text
function Index:render_all(opts)
	opts = opts or {}

	local p = new_printer(opts)
	local modules = {}

	p:header(opts.title or "JNL API Reference", 1)

	for _, name in ipairs(self:modules(opts)) do
		modules[#modules + 1] = self.raw.modules[name]
	end

	for _, module in ipairs(modules) do
		if module_has_content(module) then
			dump_module_body(p, module, opts)
		end
	end

	local types = relevant_types(
		self,
		modules,
		opts.types or "direct"
	)

	if #types > 0 then
		p:header("Types", 2)

		for _, type_doc in ipairs(types) do
			dump_type(self, p, type_doc, opts)
		end
	end

	return p:string()
end

---Write a rendered module reference to an output callback.
---@param name string Module name or suffix.
---@param opts? table Rendering options; `out` defaults to `io.write`.
---@return boolean ok
---@return string? error
function Index:dump_module(name, opts)
	opts = opts or {}
	local text, err = self:render_module(name, opts)
	if not text then return false, err end
	(opts.out or io.write)(text)
	return true
end

---Write a rendered package reference to an output callback.
---@param prefix string Dotted package prefix.
---@param opts? table Rendering options; `out` defaults to `io.write`.
function Index:dump_package(prefix, opts)
	opts = opts or {}
	(opts.out or io.write)(self:render_package(prefix, opts))
end

---Write the complete rendered reference to an output callback.
---@param opts? table Rendering options; `out` defaults to `io.write`.
function Index:dump_all(opts)
	opts = opts or {}
	(opts.out or io.write)(self:render_all(opts))
end

---Wrap a raw scanner result in the public documentation index API.
---@param raw table Raw index returned by `jnl.doc.scanner.scan`.
---@return DocIndex index
function M.from_raw(raw)
	assert(type(raw) == "table", "doc.from_raw: expected a raw scanner index")
	return setmetatable({ raw = raw }, Index)
end

---Scan source modules and return a queryable documentation index.
---
---Example:
---
---    local docs = doc.scan({ packages = { "jnl" } })
---    docs:dump_module("mesh2d.tri")
---@param opts table Scanner options accepted by `jnl.doc.scanner.scan`.
---@return DocIndex index
function M.scan(opts)
	return M.from_raw(Scanner.scan(opts or {}))
end

---Resolve a module name through package.path without loading it.
---@param module_name string Dotted Lua module name.
---@param package_path? string Search path; defaults to package.path.
---@return string? path
---@return string? error
function M.resolve_module(module_name, package_path)
	return Scanner.resolve_module(module_name, package_path)
end

---Discover source modules below a package prefix.
---@param package_name string Dotted package prefix.
---@param opts? table Discovery options.
---@return string[] modules
---@return table[] diagnostics
function M.discover_package(package_name, opts)
	return Scanner.discover_package(package_name, opts)
end

M.Index = Index

return M
