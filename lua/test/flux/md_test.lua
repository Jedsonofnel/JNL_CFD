-- lua/flux/md_test.lua - Unit tests for flux.md.
-- <jed@nelson.ac> // 2026-06-16

local h = require("test.harness")
local md = require("flux.md")

--
-- Front matter
--

h.describe("front matter: scalar types", function()
    h.it("parses a string value", function()
        h.expect(md.parse("---\ntitle: Hello World\n---\n").meta.title)
            .equals("Hello World")
    end)

    h.it("parses an integer value", function()
        h.expect(md.parse("---\nversion: 3\n---\n").meta.version).equals(3)
    end)

    h.it("parses a float value", function()
        h.expect(md.parse("---\nweight: 1.5\n---\n").meta.weight).equals(1.5)
    end)

    h.it("parses boolean true", function()
        h.expect(md.parse("---\ndraft: true\n---\n").meta.draft).is_truthy()
    end)

    h.it("parses boolean false", function()
        h.expect(md.parse("---\npublished: false\n---\n").meta.published)
            .is_falsy()
    end)

    h.it("strips surrounding double quotes", function()
        h.expect(md.parse('---\nauthor: "Jed Nelson"\n---\n').meta.author)
            .equals("Jed Nelson")
    end)

    h.it("strips surrounding single quotes", function()
        h.expect(md.parse("---\nauthor: 'Jed Nelson'\n---\n").meta.author)
            .equals("Jed Nelson")
    end)
end)

h.describe("front matter: lists", function()
    local src = "---\ntags:\n- lua\n- cfd\n- fvm\n---\n"

    h.it("parses a flat scalar list", function()
        local tags = md.parse(src).meta.tags
        h.expect(tags[1]).equals("lua")
        h.expect(tags[2]).equals("cfd")
        h.expect(tags[3]).equals("fvm")
    end)

    h.it("list length is correct", function()
        h.expect(#md.parse(src).meta.tags).equals(3)
    end)
end)

h.describe("front matter: edge cases", function()
    h.it("returns empty meta when no front matter is present", function()
        h.expect(md.parse("# Hello\n").meta.title).is_nil()
    end)

    h.it("does not render front matter content into html", function()
        local doc = md.parse("---\ntitle: Hidden\n---\n# Body\n")
        h.expect(doc.html:find("Hidden")).is_nil()
    end)

    h.it("body following front matter is parsed normally", function()
        local doc = md.parse("---\ntitle: T\n---\n# Body\n")
        h.expect(doc.html:find("<h1")).is_not_nil()
    end)

    h.it("source with no closing delimiter is treated as body-only", function()
        -- incomplete front matter delimiter: no closing ---
        local doc = md.parse("---\norphan\n")
        h.expect(doc.meta.orphan).is_nil()
    end)
end)

--
-- Headings
--

h.describe("headings", function()
    h.it("h1 produces h1 tags with an id attribute", function()
        h.expect(md.render("# Solver Overview\n"))
            .equals('<h1 id="solver-overview">Solver Overview</h1>')
    end)

    h.it("heading levels h1 through h6 are all recognised", function()
        for level = 1, 6 do
            local html = md.render(string.rep("#", level) .. " T\n")
            h.expect(html:find("<h" .. level)).is_not_nil()
            h.expect(html:find("</h" .. level)).is_not_nil()
        end
    end)

    h.it("slug is lowercased", function()
        h.expect(md.parse("# JNLCFD\n").toc[1].id).equals("jnlcfd")
    end)

    h.it("slug converts spaces to hyphens", function()
        h.expect(md.parse("## Finite Volume Method\n").toc[1].id)
            .equals("finite-volume-method")
    end)

    h.it("trailing hashes are stripped from heading text", function()
        local html = md.render("## Intro ##\n")
        h.expect(html:find("##")).is_nil()
        h.expect(html:find(">Intro<")).is_not_nil()
    end)

    h.it("inline markup in headings is rendered", function()
        local html = md.render("# The **Core** Loop\n")
        h.expect(html:find("<strong>Core</strong>")).is_not_nil()
    end)
end)

--
-- Table of contents
--

h.describe("table of contents", function()
    local src = "# Top\n\n## Section A\n\n### Detail\n\n## Section B\n"
    local doc = md.parse(src)

    h.it("toc has one entry per heading", function()
        h.expect(#doc.toc).equals(4)
    end)

    h.it("toc entries record the correct level", function()
        h.expect(doc.toc[1].level).equals(1)
        h.expect(doc.toc[2].level).equals(2)
        h.expect(doc.toc[3].level).equals(3)
        h.expect(doc.toc[4].level).equals(2)
    end)

    h.it("toc entries carry the plain unrendered text", function()
        h.expect(doc.toc[1].text).equals("Top")
        h.expect(doc.toc[2].text).equals("Section A")
    end)

    h.it("toc entries carry slugified ids", function()
        h.expect(doc.toc[2].id).equals("section-a")
        h.expect(doc.toc[4].id).equals("section-b")
    end)

    h.it("toc is empty for a document with no headings", function()
        h.expect(#md.parse("Just a paragraph.\n").toc).equals(0)
    end)
end)

--
-- Paragraphs
--

h.describe("paragraphs", function()
    h.it("plain text is wrapped in p tags", function()
        h.expect(md.render("Hello world.\n")).equals("<p>Hello world.</p>")
    end)

    h.it("two blank-line-separated blocks become two p elements", function()
        local html = md.render("First.\n\nSecond.\n")
        h.expect(html:find("<p>First")).is_not_nil()
        h.expect(html:find("<p>Second")).is_not_nil()
    end)

    h.it(
        "soft line breaks within a paragraph are joined with a space",
        function()
            local html = md.render("Line one\nLine two\n")
            h.expect(html:find("Line one Line two")).is_not_nil()
        end
    )

    h.it(
        "multiple consecutive blank lines do not produce extra elements",
        function()
            local html = md.render("A\n\n\n\nB\n")
            local _, count = html:gsub("<p>", "")
            h.expect(count).equals(2)
        end
    )
end)

--
-- Inline markup
--

h.describe("inline: bold", function()
    h.it("double asterisks produce strong", function()
        h.expect(md.render("**bold**")).equals("<p><strong>bold</strong></p>")
    end)

    h.it("double underscores produce strong", function()
        h.expect(md.render("__bold__")).equals("<p><strong>bold</strong></p>")
    end)
end)

h.describe("inline: italic", function()
    h.it("single asterisk produces em", function()
        h.expect(md.render("*italic*")).equals("<p><em>italic</em></p>")
    end)
end)

h.describe("inline: code spans", function()
    h.it("backtick span produces code tags", function()
        h.expect(md.render("`flux`")).equals("<p><code>flux</code></p>")
    end)

    h.it("markup inside a code span is not processed", function()
        local html = md.render("`**not bold**`")
        h.expect(html:find("<strong>")).is_nil()
        h.expect(html:find("<code>")).is_not_nil()
    end)

    h.it("code span content is not html-escaped a second time", function()
        -- The & in the span should appear as &amp; once, not double-escaped
        local html = md.render("`a & b`")
        h.expect(html:find("&amp;&amp;")).is_nil()
    end)
end)

h.describe("inline: links", function()
    h.it("basic link produces an anchor tag", function()
        h.expect(md.render("[JNLCFD](https://jnl.ac)"))
            .equals('<p><a href="https://jnl.ac">JNLCFD</a></p>')
    end)

    h.it("link with title emits a title attribute", function()
        local html = md.render('[docs](https://jnl.ac "Documentation")')
        h.expect(html:find('title="Documentation"')).is_not_nil()
        h.expect(html:find('href="https://jnl%.ac"')).is_not_nil()
    end)
end)

h.describe("inline: html escaping", function()
    h.it("ampersands are escaped to &amp;", function()
        h.expect(md.render("a & b")).equals("<p>a &amp; b</p>")
    end)

    h.it("less-than is escaped to &lt;", function()
        h.expect(md.render("a < b")).equals("<p>a &lt; b</p>")
    end)

    h.it("greater-than is escaped to &gt;", function()
        h.expect(md.render("a > b")).equals("<p>a &gt; b</p>")
    end)
end)

--
-- Fenced code blocks
--

h.describe("fenced code blocks", function()
    h.it("block without language produces pre/code with no class", function()
        local html = md.render("```\nhello\n```\n")
        h.expect(html:find("<pre><code>")).is_not_nil()
    end)

    h.it("block with language adds a language- class", function()
        local html = md.render("```lua\nlocal x = 1\n```\n")
        h.expect(html:find('class="language%-lua"')).is_not_nil()
    end)

    h.it("inline markup inside a code block is not processed", function()
        local html = md.render("```\n**not bold**\n```\n")
        h.expect(html:find("<strong>")).is_nil()
        h.expect(html:find("%*%*not bold%*%*")).is_not_nil()
    end)

    h.it("angle brackets inside code blocks are html-escaped", function()
        local html = md.render("```\na < b > c\n```\n")
        h.expect(html:find("&lt;")).is_not_nil()
        h.expect(html:find("&gt;")).is_not_nil()
    end)

    h.it("multiline content preserves internal newlines", function()
        local html = md.render("```\nline1\nline2\n```\n")
        h.expect(html:find("line1\nline2")).is_not_nil()
    end)

    h.it("empty code block produces an empty code element", function()
        local html = md.render("```\n```\n")
        h.expect(html:find("<pre><code></code></pre>")).is_not_nil()
    end)
end)

--
-- Unordered lists
--

h.describe("unordered lists", function()
    h.it("dash bullets produce a ul with li items", function()
        local html = md.render("- alpha\n- beta\n")
        h.expect(html:find("<ul>")).is_not_nil()
        h.expect(html:find("<li>alpha</li>")).is_not_nil()
        h.expect(html:find("<li>beta</li>")).is_not_nil()
    end)

    h.it("asterisk bullet is recognised", function()
        h.expect(md.render("* one\n"):find("<li>one</li>")).is_not_nil()
    end)

    h.it("plus bullet is recognised", function()
        h.expect(md.render("+ one\n"):find("<li>one</li>")).is_not_nil()
    end)

    h.it("inline markup in list items is rendered", function()
        local html = md.render("- **bold item**\n")
        h.expect(html:find("<strong>bold item</strong>")).is_not_nil()
    end)

    h.it(
        "indented items produce a nested sub-list inside the parent li",
        function()
            local html = md.render("- parent\n  - child\n")
            h.expect(html:find("<li>parent<ul>")).is_not_nil()
            h.expect(html:find("<li>child</li>")).is_not_nil()
        end
    )

    h.it("multiple top-level items each get their own li", function()
        local html = md.render("- one\n- two\n- three\n")
        local _, count = html:gsub("<li>", "")
        h.expect(count).equals(3)
    end)
end)

--
-- Ordered lists
--

h.describe("ordered lists", function()
    h.it("numbered items produce an ol with li items", function()
        local html = md.render("1. first\n2. second\n")
        h.expect(html:find("<ol>")).is_not_nil()
        h.expect(html:find("<li>first</li>")).is_not_nil()
        h.expect(html:find("<li>second</li>")).is_not_nil()
    end)

    h.it("indented items produce a nested sub-list", function()
        local html = md.render("1. parent\n   1. child\n")
        h.expect(html:find("<li>parent<ol>")).is_not_nil()
    end)
end)

--
-- Blockquotes
--

h.describe("blockquotes", function()
    h.it("lines prefixed with > are wrapped in blockquote tags", function()
        local html = md.render("> A wise saying.\n")
        h.expect(html:find("<blockquote>")).is_not_nil()
        h.expect(html:find("A wise saying")).is_not_nil()
    end)

    h.it("blockquote content is processed for inline markup", function()
        local html = md.render("> **important**\n")
        h.expect(html:find("<strong>important</strong>")).is_not_nil()
    end)

    h.it("headings inside a blockquote are parsed as blocks", function()
        local html = md.render("> # Heading inside quote\n")
        h.expect(html:find("<h1")).is_not_nil()
    end)

    h.it("headings inside a blockquote contribute to the toc", function()
        local doc = md.parse("> # Inner\n")
        h.expect(#doc.toc).equals(1)
        h.expect(doc.toc[1].text).equals("Inner")
    end)
end)

--
-- Thematic breaks
--

h.describe("thematic breaks", function()
    h.it("three dashes produce an hr element", function()
        h.expect(md.render("---\n")).equals("<hr />")
    end)

    h.it("three asterisks produce an hr element", function()
        h.expect(md.render("***\n")).equals("<hr />")
    end)

    h.it("three underscores produce an hr element", function()
        h.expect(md.render("___\n")).equals("<hr />")
    end)

    h.it("longer runs of dashes are also recognised", function()
        h.expect(md.render("------\n")).equals("<hr />")
    end)
end)

--
-- render and parse_file convenience
--

h.describe("render shorthand", function()
    h.it("returns a string not a table", function()
        h.expect(type(md.render("# Hello\n"))).equals("string")
    end)

    h.it("front matter content is absent from the returned string", function()
        local result = md.render("---\ntitle: Ignored\n---\n# Body\n")
        h.expect(result:find("Ignored")).is_nil()
    end)
end)

--
-- Combined document
--

h.describe("combined document", function()
    local source = [[---
title: JNLCFD Architecture
author: Jed Nelson
version: 2
tags:
- cfd
- lua
---

# Overview

A **lightweight** CFD solver with an embedded `flux` scripting layer.

## Components

- Solver core written in C
- Lua scripting layer
- VTK output for post-processing

## Usage

```lua
local flux = require "flux"
flux.serve(router, { port = 8080 })
```

---

> The solver validates against Ghia lid-driven cavity benchmarks.

]]

    local doc = md.parse(source)

    h.it("string meta fields are parsed", function()
        h.expect(doc.meta.title).equals("JNLCFD Architecture")
        h.expect(doc.meta.author).equals("Jed Nelson")
    end)

    h.it("numeric meta fields are parsed", function()
        h.expect(doc.meta.version).equals(2)
    end)

    h.it("list meta fields are parsed", function()
        h.expect(doc.meta.tags[1]).equals("cfd")
        h.expect(doc.meta.tags[2]).equals("lua")
    end)

    h.it("toc has one entry per heading", function()
        h.expect(#doc.toc).equals(3)
    end)

    h.it("toc entries are in document order", function()
        h.expect(doc.toc[1].text).equals("Overview")
        h.expect(doc.toc[2].text).equals("Components")
        h.expect(doc.toc[3].text).equals("Usage")
    end)

    h.it("bold inline markup is rendered in the body paragraph", function()
        h.expect(doc.html:find("<strong>lightweight</strong>")).is_not_nil()
    end)

    h.it("inline code span in paragraph is rendered", function()
        h.expect(doc.html:find("<code>flux</code>")).is_not_nil()
    end)

    h.it("fenced lua block has the correct language class", function()
        h.expect(doc.html:find('class="language%-lua"')).is_not_nil()
    end)

    h.it("code block content is not processed for bold markup", function()
        h.expect(doc.html:find("<strong>port</strong>")).is_nil()
    end)

    h.it("thematic break is present in output", function()
        h.expect(doc.html:find("<hr />")).is_not_nil()
    end)

    h.it("blockquote is present in output", function()
        h.expect(doc.html:find("<blockquote>")).is_not_nil()
    end)

    h.it("unordered list items are all present", function()
        h.expect(doc.html:find("<ul>")).is_not_nil()
        local _, count = doc.html:gsub("<li>", "")
        h.expect(count).equals(3)
    end)
end)
