-- test/repl_test.lua - Tests for the public JNL REPL interface
-- <jed@nelson.ac> // 2026-06-12

local h = require("test.harness")
local doc = require("jnl.doc")
local repl = require("jnl.repl")

local created_globals = {}

local function remember_global(name)
	created_globals[#created_globals + 1] = name
end

local function new_repl_with_sample_docs()
	local instance = repl.new()

	instance.doc_index = doc.scan({
		modules = {
			"test.doc_sample",
		},
	})

	return instance
end

h.after_each(function()
	for _, name in ipairs(created_globals) do
		_G[name] = nil
	end

	created_globals = {}
end)

h.describe("REPL construction", function()
	h.it("creates an independent REPL instance", function()
		local a = repl.new()
		local b = repl.new()

		h.expect(a).is_not_nil()
		h.expect(b).is_not_nil()
		h.expect(a).not_equals(b)
	end)

	h.it("installs standard commands", function()
		local instance = repl.new()

		h.expect(instance.commands.help).is_not_nil()
		h.expect(instance.commands.doc).is_not_nil()
		h.expect(instance.commands.llm).is_not_nil()
		h.expect(instance.commands.quit).is_not_nil()
		h.expect(instance.commands.usage).is_not_nil()
	end)

	h.it("installs standard registered values", function()
		local instance = repl.new()

		h.expect(instance.registry.pp).is_not_nil()
		h.expect(instance.registry.remember).is_not_nil()
	end)

	h.it("uses the configured help width", function()
		local instance = repl.new({
			width = 96,
		})

		h.expect(instance.help_width).equals(96)
	end)
end)

h.describe("REPL registration", function()
	h.it("exposes a value as a global", function()
		local instance = repl.new()
		local value = {}

		remember_global("sample-value")

		instance:register(
			"sample-value",
			value,
			"A sample value."
		)

		h.expect(_G["sample-value"]).equals(value)
	end)

	h.it("stores the value in the help registry", function()
		local instance = repl.new()
		local value = {}

		remember_global("sample-entry")

		instance:register(
			"sample-entry",
			value,
			"A sample entry."
		)

		local entry = instance.registry["sample-entry"]

		h.expect(entry).is_not_nil()
		h.expect(entry.value).equals(value)
		h.expect(entry.doc).equals("A sample entry.")
	end)

	h.it("returns the registered value", function()
		local instance = repl.new()
		local value = {}

		remember_global("returned-value")

		local returned = instance:register(
			"returned-value",
			value,
			false
		)

		h.expect(returned).equals(value)
	end)

	h.it("accepts literal documentation", function()
		local instance = repl.new()

		remember_global("literal-doc")

		instance:register(
			"literal-doc",
			function() end,
			"Literal help text."
		)

		h.expect(
			instance.registry["literal-doc"].doc
		).equals("Literal help text.")
	end)

	h.it("suppresses documentation lookup with false", function()
		local instance = new_repl_with_sample_docs()

		remember_global("default_scheme")

		instance:register(
			"default_scheme",
			function() end,
			false
		)

		h.expect(
			instance.registry.default_scheme.doc
		).equals("")
	end)

	h.it("looks up documentation by registered name", function()
		local instance = new_repl_with_sample_docs()

		remember_global("default_scheme")

		instance:register(
			"default_scheme",
			function() end
		)

		h.expect(
			instance.registry.default_scheme.doc
		).equals("Return the default scheme.")
	end)

	h.it("looks up documentation from an explicit symbol", function()
		local instance = new_repl_with_sample_docs()

		remember_global("scheme")

		instance:register(
			"scheme",
			function() end,
			{
				from = "test.doc_sample.default_scheme",
			}
		)

		h.expect(
			instance.registry.scheme.doc
		).equals("Return the default scheme.")
	end)

	h.it("allows literal documentation in a table", function()
		local instance = repl.new()

		remember_global("table-doc")

		instance:register(
			"table-doc",
			42,
			{
				doc = "Documentation from a specification table.",
			}
		)

		h.expect(
			instance.registry["table-doc"].doc
		).equals(
			"Documentation from a specification table."
		)
	end)

	h.it("rejects an empty registration name", function()
		local instance = repl.new()

		h.expect(function()
			instance:register("", 42)
		end).throws("name must be a non-empty string")
	end)
end)

h.describe("Default REPL facade", function()
	h.it("returns the same default instance", function()
		h.expect(repl.default()).equals(repl.default())
	end)

	h.it("module registration uses the default instance", function()
		local value = {}

		remember_global("default-instance-value")

		repl.register(
			"default-instance-value",
			value,
			"Default instance value."
		)

		local entry = repl.default().registry[
		"default-instance-value"
		]

		h.expect(entry).is_not_nil()
		h.expect(entry.value).equals(value)
	end)

	h.it("module special stores a global", function()
		remember_global("*sample-result*")

		local value = repl.special(
			"*sample-result*",
			123,
			false
		)

		h.expect(value).equals(123)
		h.expect(_G["*sample-result*"]).equals(123)
	end)
end)

h.describe("REPL usage", function()
	h.it("returns literal usage text", function()
		local instance = repl.new()

		instance:usage("Run `(demo)`.")

		h.expect(instance:usage_string())
			.equals("Run `(demo)`.")
	end)

	h.it("calls a usage provider", function()
		local instance = repl.new()

		instance:usage(function(active)
			h.expect(active).equals(instance)
			return "Generated usage."
		end)

		h.expect(instance:usage_string())
			.equals("Generated usage.")
	end)

	h.it("accepts an object with string method", function()
		local instance = repl.new()

		instance:usage({
			string = function()
				return "Object usage."
			end,
		})

		h.expect(instance:usage_string())
			.equals("Object usage.")
	end)

	h.it("accepts an object with usage_string method", function()
		local instance = repl.new()

		instance:usage({
			usage_string = function()
				return "Provider usage."
			end,
		})

		h.expect(instance:usage_string())
			.equals("Provider usage.")
	end)

	h.it("returns fallback usage when none is registered", function()
		local instance = repl.new()
		local text = instance:usage_string()

		h.expect(
			text:find(
				"No study-specific usage has been registered.",
				1,
				true
			)
		).is_not_nil()
	end)
end)

h.describe("REPL commands", function()
	h.it("registers a custom command", function()
		local instance = repl.new()
		local called = false

		instance:command(
			"sample",
			function(active, argument)
				h.expect(active).equals(instance)
				h.expect(argument).equals("hello")
				called = true
			end,
			",sample <text>",
			"Run the sample command."
		)

		instance.commands.sample.fn(
			instance,
			"hello"
		)

		h.expect(called).is_truthy()
		h.expect(instance.commands.sample.usage)
			.equals(",sample <text>")
	end)

	h.it("rejects a non-function command callback", function()
		local instance = repl.new()

		h.expect(function()
			instance:command("bad", 42)
		end).throws("callback must be a function")
	end)

	h.it("stop marks the REPL for exit", function()
		local instance = repl.new()

		instance:stop()

		h.expect(instance.quit).is_truthy()
	end)
end)
