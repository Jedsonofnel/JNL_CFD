-- lua/flux/html_test.lua - Unit tests for flux.html.
-- <jed@nelson.ac> // 2026-06-13

local h = require "test.harness"
local H = require "flux.html"

--
-- Simple elements
--

h.describe("simple elements", function()
	h.it("string shorthand wraps content in open and close tags", function()
		h.expect(H.p "hello").equals("<p>hello</p>")
	end)

	h.it("nil argument produces an empty element", function()
		h.expect(H.div()).equals("<div></div>")
	end)

	h.it("empty children table produces an empty element", function()
		h.expect(H.div {}).equals("<div></div>")
	end)

	h.it("number argument is coerced to a string", function()
		h.expect(H.td(42)).equals("<td>42</td>")
	end)

	h.it("arbitrary tag names are generated on demand", function()
		h.expect(H.foo "bar").equals("<foo>bar</foo>")
	end)

	h.it("child list with no attrs concatenates children", function()
		h.expect(H.div { H.p "a", H.p "b" })
			.equals("<div><p>a</p><p>b</p></div>")
	end)

	h.it("nested elements produce valid markup", function()
		h.expect(H.ul { H.li "one", H.li "two" })
			.equals("<ul><li>one</li><li>two</li></ul>")
	end)
end)

--
-- Attribute serialisation
--

h.describe("attribute serialisation", function()
	h.it("attrs with a string child", function()
		h.expect(H.a { href = "/" } "Home")
			.equals('<a href="/">Home</a>')
	end)

	h.it("attrs with a children table", function()
		h.expect(H.div { class = "wrap" } { H.p "x" })
			.equals('<div class="wrap"><p>x</p></div>')
	end)

	h.it("attrs with nil child produces an empty element", function()
		h.expect(H.div { class = "x" } ())
			.equals('<div class="x"></div>')
	end)

	h.it("attr keys are sorted alphabetically for deterministic output", function()
		h.expect(H.a { href = "/guide", class = "link" } "Guide")
			.equals('<a class="link" href="/guide">Guide</a>')
	end)

	h.it("true value emits a bare attribute name", function()
		h.expect(H.script { defer = true, src = "/app.js" } "")
			.equals('<script defer src="/app.js"></script>')
	end)

	h.it("false value omits the attribute entirely", function()
		h.expect(H.p { class = false } "x")
			.equals("<p>x</p>")
	end)
end)

--
-- Void elements
--

h.describe("void elements", function()
	h.it("bare call produces a self-closing tag", function()
		h.expect(H.br()).equals("<br />")
	end)

	h.it("empty children table still produces a self-closing tag", function()
		h.expect(H.hr {}).equals("<hr />")
	end)

	h.it("attrs produce a self-closing tag with attributes", function()
		h.expect(H.input { type = "text" })
			.equals('<input type="text" />')
	end)

	h.it("true attr on a void element emits a bare attribute name", function()
		h.expect(H.input { type = "checkbox", checked = true })
			.equals("<input checked type=\"checkbox\" />")
	end)

	h.it("link element with rel and href", function()
		h.expect(H.link { rel = "stylesheet", href = "/style.css" })
			.equals('<link href="/style.css" rel="stylesheet" />')
	end)
end)

--
-- String formatting
--

h.describe("string formatting", function()
	h.it("single argument is returned unchanged", function()
		h.expect(H.p "no format").equals("<p>no format</p>")
	end)

	h.it("extra arguments trigger string.format", function()
		h.expect(H.p("item %d of %d", 3, 10))
			.equals("<p>item 3 of 10</p>")
	end)

	h.it("format string works after attrs", function()
		h.expect(H.p { class = "count" } ("%d results", 42))
			.equals('<p class="count">42 results</p>')
	end)
end)

--
-- Raw passthrough
--

h.describe("raw passthrough", function()
	h.it("raw string is included without escaping", function()
		h.expect(H.div { H.raw("<em>hi</em>") })
			.equals("<div><em>hi</em></div>")
	end)

	h.it("raw works as a direct child alongside normal elements", function()
		h.expect(H.div { H.h1 "Title", H.raw("<p>body</p>") })
			.equals("<div><h1>Title</h1><p>body</p></div>")
	end)

	h.it("raw accepts a non-string by coercing via tostring", function()
		h.expect(H.span { H.raw(99) }).equals("<span>99</span>")
	end)
end)

--
-- Conditional rendering
--

h.describe("conditional rendering", function()
	h.it("when returns content when condition is truthy", function()
		h.expect(H.when(true, H.span "yes")).equals("<span>yes</span>")
	end)

	h.it("when returns an empty string when condition is false", function()
		h.expect(H.when(false, H.span "yes")).equals("")
	end)

	h.it("when returns an empty string when condition is nil", function()
		h.expect(H.when(nil, H.span "yes")).equals("")
	end)

	h.it("when does not call a function child when condition is falsy", function()
		local called = false
		H.when(false, function()
			called = true
			return H.span "x"
		end)
		h.expect(called).is_falsy("deferred function must not be called")
	end)

	h.it("when calls a function child and renders result when truthy", function()
		local result = H.when(true, function()
			return H.span "deferred"
		end)
		h.expect(result).equals("<span>deferred</span>")
	end)
end)

--
-- List mapping
--

h.describe("list mapping", function()
	h.it("map renders each item and concatenates results", function()
		local result = H.map({ "a", "b", "c" }, function(v)
			return H.li(v)
		end)
		h.expect(result).equals("<li>a</li><li>b</li><li>c</li>")
	end)

	h.it("map works as a direct child of an element", function()
		local items = { "x", "y" }
		h.expect(H.ul { H.map(items, H.li) })
			.equals("<ul><li>x</li><li>y</li></ul>")
	end)

	h.it("map passes the one-based index as the second argument", function()
		local indices = {}
		H.map({ "a", "b", "c" }, function(_, i)
			indices[#indices + 1] = i
			return ""
		end)
		h.expect(indices[1]).equals(1)
		h.expect(indices[2]).equals(2)
		h.expect(indices[3]).equals(3)
	end)

	h.it("map over an empty table returns an empty string", function()
		h.expect(H.map({}, H.li)).equals("")
	end)
end)

--
-- Class string builder
--

h.describe("class string builder", function()
	h.it("plain strings are joined with spaces", function()
		h.expect(H.cls("a", "b", "c")).equals("a b c")
	end)

	h.it("empty strings are skipped", function()
		h.expect(H.cls("a", "", "b")).equals("a b")
	end)

	h.it("truthy conditional keys are included", function()
		h.expect(H.cls({ active = true, disabled = false })).equals("active")
	end)

	h.it("conditional keys are sorted for deterministic output", function()
		h.expect(H.cls({ zebra = true, alpha = true, mid = true }))
			.equals("alpha mid zebra")
	end)

	h.it("strings and conditionals can be mixed", function()
		h.expect(H.cls("btn", { active = true, hidden = false }))
			.equals("btn active")
	end)

	h.it("no arguments returns an empty string", function()
		h.expect(H.cls()).equals("")
	end)
end)

--
-- Fragments
--

h.describe("fragments", function()
	h.it("fragment concatenates nodes without a wrapper element", function()
		h.expect(H.fragment(H.p "a", H.p "b"))
			.equals("<p>a</p><p>b</p>")
	end)

	h.it("fragment with a single node returns that node unchanged", function()
		h.expect(H.fragment(H.h1 "title")).equals("<h1>title</h1>")
	end)

	h.it("fragment with no arguments returns an empty string", function()
		h.expect(H.fragment()).equals("")
	end)
end)

--
-- Environment injection
--

h.describe("environment injection", function()
	h.it("tag functions are available as bare names", function()
		local _ENV = H.env()
		h.expect(div "x").equals("<div>x</div>")
		h.expect(p "hello").equals("<p>hello</p>")
		h.expect(h1 "title").equals("<h1>title</h1>")
	end)

	h.it("the Lua table library is preserved under its normal name", function()
		local _ENV = H.env()
		h.expect(table.concat({ "a", "b", "c" }, "-")).equals("a-b-c")
	end)

	h.it("H.table produces the HTML table element", function()
		h.expect(H.table { H.tr { H.td "cell" } })
			.equals("<table><tr><td>cell</td></tr></table>")
	end)

	h.it("F is available as an alias for string.format", function()
		local _ENV = H.env()
		h.expect(F("hello %s", "world")).equals("hello world")
	end)

	h.it("doctype is the HTML5 declaration string", function()
		h.expect(H.doctype).equals("<!DOCTYPE html>")
	end)

	h.it("doctype is available as a bare name inside env", function()
		local _ENV = H.env()
		h.expect(doctype).equals("<!DOCTYPE html>")
	end)

	h.it("extra entries are merged into the env", function()
		local _ENV = H.env { site_name = "JNLCFD" }
		h.expect(site_name).equals("JNLCFD")
	end)

	h.it("standard globals remain accessible via fallthrough", function()
		local _ENV = H.env()
		h.expect(type("x")).equals("string")
		h.expect(tostring(42)).equals("42")
	end)
end)
