-- lua/flux/server.lua - HTTP server for the Flux web framework.
-- <jed@nelson.ac> // 2026-06-13

local socket = require "socket"

--- Minimal synchronous HTTP/1.1 server backed by luasocket.
---
--- Serves one request at a time. Suitable for local and single-user use
--- such as the bin/cli --docs command. For production deployment use the
--- OpenResty backend (flux.server_ngx) instead.
local M = {}

--
-- MIME types
--

local MIME = {
	html  = "text/html; charset=utf-8",
	css   = "text/css",
	js    = "application/javascript",
	json  = "application/json",
	txt   = "text/plain",
	png   = "image/png",
	jpg   = "image/jpeg",
	jpeg  = "image/jpeg",
	svg   = "image/svg+xml",
	ico   = "image/x-icon",
	woff2 = "font/woff2",
	woff  = "font/woff",
}

--
-- Query string parsing
--

local function urldecode(s)
	return (s:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end):gsub("+", " "))
end

--- Parse a URL-encoded query string or POST body into a key-value table.
---
---   parse_qs("q=hello+world&page=2")  ->  { q = "hello world", page = "2" }
---
--- Returns an empty table for nil or empty input.
---@param s string?
---@return table<string, string>
function M.parse_qs(s)
	local t = {}
	for pair in (s or ""):gmatch("[^&]+") do
		local k, v = pair:match("([^=]+)=?(.*)")
		if k then
			t[urldecode(k)] = urldecode(v or "")
		end
	end
	return t
end

--
-- Request parsing
--

-- Parse one HTTP request from a connected client socket.
-- Returns a request table or nil when the client sends no data.
local function parse(client)
	local line = client:receive("*l")
	if not line then return nil end

	local method, path = line:match("(%u+) ([^ ]+) HTTP/")
	if not method then return nil end

	local headers = {}
	repeat
		local hline = client:receive("*l") or ""
		hline = hline:gsub("\r", "")
		local k, v = hline:match("([^:]+):%s*(.*)")
		if k then headers[k:lower()] = v end
	until hline == ""

	local body = ""
	local len  = tonumber(headers["content-length"])
	if len and len > 0 then
		body = client:receive(len) or ""
	end

	local clean = path:match("([^?]+)") or path

	return {
		method  = method,
		path    = clean,
		query   = path:match("%?(.*)") or "",
		headers = headers,
		body    = body,
		is_htmx = headers["hx-request"] == "true",
		params  = {},
	}
end

--
-- Response
--

local function send(client, status, content_type, body)
	client:send(table.concat({
		"HTTP/1.1 " .. status,
		"Content-Type: " .. content_type,
		"Content-Length: " .. #body,
		"Connection: close",
		"",
		body,
	}, "\r\n"))
end

-- Build the response object passed to every handler.
local function make_res(client, req)
	local res = {}

	-- Send an HTML response with an optional status line.
	function res.html(body, status)
		send(client, status or "200 OK", MIME.html, body)
	end

	-- Send a JSON response with an optional status line.
	function res.json(body, status)
		send(client, status or "200 OK", MIME.json, body)
	end

	-- Send a redirect. Status defaults to "302 Found".
	function res.redirect(url, status)
		client:send(table.concat({
			"HTTP/1.1 " .. (status or "302 Found"),
			"Location: " .. url,
			"Content-Length: 0",
			"Connection: close",
			"",
			"",
		}, "\r\n"))
	end

	-- Send a 404 response.
	function res.not_found()
		send(client, "404 Not Found", MIME.html, "<h1>Not found</h1>")
	end

	-- Serve a file from disk by path.
	-- Strips path traversal sequences before opening.
	function res.file(path)
		path = path:gsub("%.%.", "")
		local f = io.open(path, "rb")
		if not f then
			res.not_found()
			return
		end
		local body = f:read("*a")
		f:close()
		local ext = path:match("%.(%w+)$") or "html"
		send(client, "200 OK", MIME[ext] or "text/plain", body)
	end

	-- Send fragment for HTMX requests, full_page for normal browser requests.
	function res.htmx(fragment, full_page)
		res.html(req.is_htmx and fragment or full_page)
	end

	-- Send fragment for HTMX requests, or wrap it with layout_fn for normal requests.
	-- Extra args are forwarded to layout_fn after fragment.
	function res.page(fragment, layout_fn, ...)
		res.html(req.is_htmx and fragment or layout_fn(fragment, ...))
	end

	return res
end

--
-- Server
--

--- Start the HTTP server and block indefinitely, serving requests in a loop.
---
---   local r = require("flux.router").new()
---   r:get("/", function(req, res) res.html("<h1>Hello</h1>") end)
---   require("flux.server").serve(r, { port = 8080 })
---
--- Options:
---   host          Bind address. Default "127.0.0.1".
---   port          Port number. Default 8080.
---   static        URL prefix for static files. Default "/static/".
---   static_root   Directory to serve static files from. Default "web/static".
---@param r FluxRouter
---@param opts? table
function M.serve(r, opts)
	opts                = opts or {}
	local host          = opts.host or "127.0.0.1"
	local port          = opts.port or 8080
	local static_prefix = opts.static or "/static/"
	local static_root   = opts.static_root or "web/static"

	local srv           = assert(socket.bind(host, port))
	io.write(string.format("flux: listening on http://%s:%d\n", host, port))

	while true do
		local client = srv:accept()
		if client then
			client:settimeout(10)
			local req = parse(client)
			if req then
				local res = make_res(client, req)
				if req.path:sub(1, #static_prefix) == static_prefix then
					local rel = req.path:sub(#static_prefix + 1)
					res.file(static_root .. "/" .. rel)
				else
					local matched = r:dispatch(req, res)
					if not matched then
						res.not_found()
					end
				end
			end
			client:close()
		end
	end
end

return M
