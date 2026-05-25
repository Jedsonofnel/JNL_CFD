-- jnl/gp.lua - gnuplot driver via popen
-- <jed@nelson> // 2026-05-22

local M = {}

--
-- Pipe management
--

local function gp_open()
	local pipe = io.popen("gnuplot 2>/dev/null", "w")
	if not pipe then
		io.stderr:write([[
[jnl.gp] gnuplot not found. Install with:
  Arch/EndeavourOS:  sudo pacman -S gnuplot
  Debian/Ubuntu:     sudo apt install gnuplot
  macOS:             brew install gnuplot
]])
		error("[jnl.gp] gnuplot not found", 2)
	end
	return pipe
end

local function gp_send(pipe, fmt, ...)
	pipe:write(string.format(fmt .. "\n", ...))
end

--
-- inline data
--

local function write_xy(pipe, xs, ys)
	assert(#xs == #ys, "xs and ys must be the same length")
	for i = 1, #xs do
		pipe:write(string.format("%.10g %.10g\n", xs[i], ys[i]))
	end
	pipe:write("e\n")
end

--
-- Series builder
--

function M.series(xs, ys, opts)
	opts = opts or {}
	return {
		xs    = xs,
		ys    = ys,
		title = opts.title,
		style = opts.style or "linespoints",
		color = opts.color,
		lw    = opts.lw,
		pt    = opts.pt,
		ps    = opts.ps,
		dt    = opts.dt, -- dashtype  e.g. 2
	}
end

local function series_cmd(s)
	local t = { "'-'" }
	table.insert(t, "with " .. (s.style or "linespoints"))
	if s.title then
		table.insert(t, string.format("title %q", s.title))
	else
		table.insert(t, "notitle")
	end
	if s.color then table.insert(t, string.format("lc rgb %q", s.color)) end
	if s.lw then table.insert(t, "lw " .. s.lw) end
	if s.pt then table.insert(t, "pt " .. s.pt) end
	if s.ps then table.insert(t, "ps " .. s.ps) end
	if s.dt then table.insert(t, "dt " .. s.dt) end
	return table.concat(t, " ")
end

--
-- Output helper
--

---Write one or more series to a csv
--- - M.write_csv(path, series_list)
--- - M.write_csv(path, xs, ys, header?)
function M.write_csv(path, xs_or_series, ys, header)
	local f = io.open(path, "w")
	if not f then error(string.format("[jnl.gp] cannot open %q for writing", path)) end

	if type(xs_or_series) == "table" and xs_or_series[1] and xs_or_series[1].xs then
		-- list of series structs
		local series_list = xs_or_series
		-- header from titles
		local heads = {}
		for _, s in ipairs(series_list) do
			table.insert(heads, "x_" .. (s.title or #heads + 1))
			table.insert(heads, "y_" .. (s.title or #heads + 1))
		end
		f:write(table.concat(heads, ",") .. "\n")
		local nrows = 0
		for _, s in ipairs(series_list) do
			if #s.xs > nrows then nrows = #s.xs end
		end
		for i = 1, nrows do
			local row = {}
			for _, s in ipairs(series_list) do
				table.insert(row, s.xs[i] and string.format("%.10g", s.xs[i]) or "")
				table.insert(row, s.ys[i] and string.format("%.10g", s.ys[i]) or "")
			end
			f:write(table.concat(row, ",") .. "\n")
		end
	else
		-- simple xs, ys path
		local xs = xs_or_series
		assert(#xs == #ys, "xs and ys must be the same length")
		f:write((header or "x,y") .. "\n")
		for i = 1, #xs do
			f:write(string.format("%.10g,%.10g\n", xs[i], ys[i]))
		end
	end

	f:close()
	io.write(string.format("[jnl.gp] csv  → %s\n", path))
end

--
-- Figure
--

local Figure = {}
Figure.__index = Figure

function M.figure(opts)
	opts = opts or {}
	return setmetatable({
		_series = {},
		_opts   = opts, -- title, xlabel, ylabel, xrange, yrange, grid, key, logx, logy
	}, Figure)
end

-- fig:add(xs, ys, opts)   or   fig:add(series)
function Figure:add(xs_or_series, ys, opts)
	if type(xs_or_series) == "table" and xs_or_series.xs then
		-- already a series struct
		table.insert(self._series, xs_or_series)
	else
		table.insert(self._series, M.series(xs_or_series, ys, opts))
	end
	return self -- chainable
end

function Figure:_emit(pipe)
	local o = self._opts

	-- terminal is set by caller before _emit
	if o.title then gp_send(pipe, "set title %q", o.title) end
	if o.xlabel then gp_send(pipe, "set xlabel %q", o.xlabel) end
	if o.ylabel then gp_send(pipe, "set ylabel %q", o.ylabel) end
	if o.xrange then gp_send(pipe, "set xrange [%g:%g]", o.xrange[1], o.xrange[2]) end
	if o.yrange then gp_send(pipe, "set yrange [%g:%g]", o.yrange[1], o.yrange[2]) end
	if o.grid then pipe:write("set grid\n") end
	if o.key == false then pipe:write("unset key\n") end
	if o.logx then pipe:write("set logscale x\n") end
	if o.logy then pipe:write("set logscale y\n") end

	assert(#self._series > 0, "[jnl.gp] nothing to plot")

	local cmds = {}
	for _, s in ipairs(self._series) do
		table.insert(cmds, series_cmd(s))
	end
	pipe:write("plot " .. table.concat(cmds, ", \\\n     ") .. "\n")

	for _, s in ipairs(self._series) do
		write_xy(pipe, s.xs, s.ys)
	end
end

-- fig:show()   – persistent interactive window
function Figure:show()
	local pipe = gp_open()
	pipe:write("set terminal wxt persist\n")
	self:_emit(pipe)
	pipe:close()
end

-- fig:save(path, opts?)
--   auto-detects terminal from extension: .png .svg .pdf .eps
--   opts.size = {w, h}  (pixels for raster, pts for vector)
--   opts.terminal = "pngcairo size 1200,800 font 'Arial,12'"  (full override)
function Figure:save(path, opts)
	opts = opts or {}
	local pipe = gp_open()

	local term
	if opts.terminal then
		term = opts.terminal
	else
		local ext = (path:match("%.(%a+)$") or "png"):lower()
		local sz  = opts.size
			and string.format(" size %d,%d", opts.size[1], opts.size[2])
			or ""
		local map = {
			png = "pngcairo" .. sz,
			svg = "svg" .. sz,
			pdf = "pdfcairo" .. sz,
			eps = "epscairo" .. sz,
		}
		term      = map[ext] or ("pngcairo" .. sz)
	end

	gp_send(pipe, "set terminal %s", term)
	gp_send(pipe, "set output %q", path)
	self:_emit(pipe)
	pipe:close()
	io.write(string.format("[jnl.gp] saved → %s\n", path))
end

---Dumps all series to a csv
function Figure:write_csv(path)
	M.write_csv(path, self._series)
	return self
end

--
-- Convenience
--

function M.sample(fn, x0, x1, n)
	n = n or 200
	local xs, ys = {}, {}
	for i = 0, n do
		local x = x0 + (x1 - x0) * i / n
		xs[i + 1] = x
		ys[i + 1] = fn(x)
	end
	return xs, ys
end

--
-- API
--

M._doc = "Gnuplot driver via popen; supports interactive display, file output, and CSV export."

M._doc_subsection =
	"Build a Figure with M.figure(opts), chain :add(xs, ys, opts) calls, then call " ..
	":show() for an interactive window or :save(path) for file output. Extension on " ..
	"the save path selects the terminal automatically (.png .svg .pdf .eps). " ..
	"M.sample(fn, x0, x1, n) generates xs/ys from a Lua function for quick plotting."

M._api = {
	figure    = { args = "opts?",                   ret = "Figure",   doc = "Create a figure; opts: { title, xlabel, ylabel, xrange, yrange, grid, key, logx, logy }" },
	series    = { args = "xs, ys, opts?",           ret = "Series",   doc = "Build a series struct explicitly; opts: { title, style, color, lw, pt, ps, dt }" },
	sample    = { args = "fn, x0, x1, n?",          ret = "xs, ys",   doc = "Sample fn over [x0,x1] at n+1 points (default 200); returns two arrays" },
	write_csv = { args = "path, xs_or_series, ys?", ret = "nil",      doc = "Write xs/ys or a list of Series structs to a CSV file" },
}

M._types = {
	Figure = {
		doc         = "Chainable figure builder; holds series list and display options",
		constructor = "M.figure(opts?)",
		kind        = "table",
		methods     = {
			add       = { args = "xs, ys, opts?  |  series:Series", ret = "Figure", doc = "Append a data series; accepts raw arrays or a Series struct; chainable" },
			show      = { args = "",                                 ret = "nil",    doc = "Open a persistent interactive gnuplot window" },
			save      = { args = "path:string, opts?",              ret = "nil",    doc = "Save to file; terminal inferred from extension; opts: { size={w,h}, terminal }" },
			write_csv = { args = "path:string",                     ret = "Figure", doc = "Dump all series to CSV; chainable" },
		},
	},
	Series = {
		doc         = "Data series descriptor table",
		constructor = "M.series(xs, ys, opts?) or fig:add(xs, ys, opts)",
		kind        = "table",
		methods     = {},
	},
}

return M
