local h = require("test.harness")
local doc = require("jnl.doc")

local function scan_sample()
	return doc.scan({
		modules = { "test.doc_sample" },
	})
end

h.describe("doc scanning", function()
	h.it("finds an explicitly requested module", function()
		local docs = scan_sample()
		local module = docs:module("test.doc_sample")

		h.expect(module).is_not_nil()
		h.expect(module.name).equals("test.doc_sample")
	end)

	h.it("supports unambiguous module suffixes", function()
		local docs = scan_sample()
		local module = docs:module("doc_sample")

		h.expect(module).is_not_nil()
		h.expect(module.name).equals("test.doc_sample")
	end)

	h.it("reads the module description", function()
		local docs = scan_sample()
		local module = docs:module("test.doc_sample")

		h.expect(module.doc).equals(
			"Example geometry module used by the documentation tests."
		)
	end)
end)

h.describe("doc functions", function()
	h.it("indexes public module functions", function()
		local docs = scan_sample()

		h.expect(
			docs:symbol("test.doc_sample.builder")
		).is_not_nil()

		h.expect(
			docs:symbol("test.doc_sample.default_scheme")
		).is_not_nil()
	end)

	h.it("records parameter annotations", function()
		local docs = scan_sample()
		local fn = docs:symbol("test.doc_sample.builder")

		h.expect(fn.params[1].name).equals("name")
		h.expect(fn.params[1].type).equals("string")
	end)

	h.it("records optional parameters", function()
		local docs = scan_sample()
		local fn = docs:symbol("test.doc_sample.Builder:build")

		h.expect(fn.params[1].name).equals("count")
		h.expect(fn.params[1].optional).is_truthy()
		h.expect(fn.params[1].type).equals("integer")
	end)

	h.it("records multiple returns", function()
		local docs = scan_sample()
		local fn = docs:symbol("test.doc_sample.Builder:build")

		h.expect(#fn.returns).equals(2)
		h.expect(fn.returns[1].type).equals("string")
		h.expect(fn.returns[2].type).equals("integer")
	end)
end)

h.describe("doc types", function()
	h.it("indexes classes by qualified name", function()
		local docs = scan_sample()
		local builder = docs:type("test.doc_sample.Builder")

		h.expect(builder).is_not_nil()
		h.expect(builder.kind).equals("class")
	end)

	h.it("resolves types locally", function()
		local docs = scan_sample()
		local builder = docs:type("Builder", "test.doc_sample")

		h.expect(builder).is_not_nil()
		h.expect(builder.qualified_name).equals(
			"test.doc_sample.Builder"
		)
	end)

	h.it("records class fields", function()
		local docs = scan_sample()
		local builder = docs:type("Builder", "test.doc_sample")

		h.expect(#builder.fields).equals(2)
		h.expect(builder.fields[1].name).equals("name")
		h.expect(builder.fields[1].type).equals("string")
	end)

	h.it("attaches methods to their class", function()
		local docs = scan_sample()
		local builder = docs:type("Builder", "test.doc_sample")

		h.expect(#builder.methods).equals(2)
	end)

	h.it("infers constructors from return types", function()
		local docs = scan_sample()
		local builder = docs:type("Builder", "test.doc_sample")

		h.expect(#builder.constructors).equals(1)
		h.expect(builder.constructors[1].qualified_name)
			.equals("test.doc_sample.builder")
	end)

	h.it("indexes aliases and alternatives", function()
		local docs = scan_sample()
		local scheme = docs:type("Scheme", "test.doc_sample")

		h.expect(scheme).is_not_nil()
		h.expect(scheme.kind).equals("alias")
		h.expect(#scheme.alias_values).equals(2)
	end)
end)

h.describe("doc relevant types", function()
	h.it("includes types referenced by the module API", function()
		local docs = scan_sample()
		local types = docs:relevant_types(
			"test.doc_sample",
			"closure"
		)

		local names = {}
		for _, type_doc in ipairs(types) do
			names[#names + 1] = type_doc.qualified_name
		end

		h.expect(names).contains("test.doc_sample.Builder")
		h.expect(names).contains("test.doc_sample.Scheme")
	end)
end)

h.describe("doc rendering", function()
	h.it("renders module functions and types", function()
		local docs = scan_sample()
		local text = docs:render_module("test.doc_sample")

		h.expect(text:find(
			"test.doc_sample.builder",
			1,
			true
		)).is_not_nil()

		h.expect(text:find(
			"test.doc_sample.Builder",
			1,
			true
		)).is_not_nil()
	end)

	h.it("renders aliases", function()
		local docs = scan_sample()
		local text = docs:render_module("test.doc_sample")

		h.expect(text:find('"uds"', 1, true)).is_not_nil()
		h.expect(text:find('"cds"', 1, true)).is_not_nil()
	end)
end)

h.describe("doc audit", function()
	h.it("accepts the documented sample without warnings", function()
		local docs = scan_sample()
		local count = docs:audit()

		h.expect(count).equals(0)
	end)
end)

local function scan_visibility_samples()
	return doc.scan({
		modules = {
			"test.doc_sample",
			"test.doc_private_sample",
		},
	})
end

h.describe("doc module visibility", function()
	h.it("records module privacy", function()
		local docs = scan_visibility_samples()
		local module = docs.raw.modules[
		"test.doc_private_sample"
		]

		h.expect(module.private).is_truthy()
	end)

	h.it("hides private modules by default", function()
		local docs = scan_visibility_samples()

		h.expect(docs:modules())
			.not_contains("test.doc_private_sample")
	end)

	h.it("can include private modules explicitly", function()
		local docs = scan_visibility_samples()

		h.expect(docs:modules({
			include_private = true,
		})).contains("test.doc_private_sample")
	end)

	h.it("does not render private modules by default", function()
		local docs = scan_visibility_samples()
		local text = docs:render_all()

		h.expect(text:find(
			"test.doc_private_sample",
			1,
			true
		)).is_nil()
	end)

	h.it("renders private modules when requested", function()
		local docs = scan_visibility_samples()

		local text, err = docs:render_module(
			"test.doc_private_sample",
			{
				include_private = true,
			}
		)

		h.expect(err).is_nil()
		h.expect(text).is_not_nil()
		h.expect(text:find(
			"test.doc_private_sample.hidden",
			1,
			true
		)).is_not_nil()
	end)

	h.it("rejects direct private rendering by default", function()
		local docs = scan_visibility_samples()

		local text, err = docs:render_module(
			"test.doc_private_sample"
		)

		h.expect(text).is_nil()
		h.expect(err).is_not_nil()
	end)

	h.it("supports context-specific module exclusions", function()
		local docs = scan_visibility_samples()

		local names = docs:modules({
			exclude_modules = {
				"test.doc_sample",
			},
		})

		h.expect(names).not_contains("test.doc_sample")
	end)
end)
