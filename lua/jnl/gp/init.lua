-- jnl/gp/init.lua - gnuplot driver via popen
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
		_opts   = {
			font   = opts.font or "Arial,11",
			size   = opts.size or { 1600, 900 },
			grid   = opts.grid ~= nil and opts.grid or true,
			title  = opts.title,
			xlabel = opts.xlabel,
			ylabel = opts.ylabel,
			xrange = opts.xrange,
			yrange = opts.yrange,
			key    = opts.key,
			logx   = opts.logx,
			logy   = opts.logy,
		},
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

function Figure:hline(y, opts)
	opts = opts or {}
	return self:add(
		{ -1e30, 1e30 }, { y, y },
		{
			style = "lines",
			lw = opts.lw or 1,
			color = opts.color or "#888888",
			dt = opts.dt or 2,
			title = opts.title
		})
end

function Figure:vline(x, opts)
	opts = opts or {}
	return self:add(
		{ x, x }, { -1e30, 1e30 },
		{
			style = "lines",
			lw = opts.lw or 1,
			color = opts.color or "#888888",
			dt = opts.dt or 2,
			title = opts.title
		})
end

function Figure:_emit(pipe)
	local o = self._opts

	gp_send(pipe, "set termoption enhanced")

	-- terminal is set by caller before _emit
	if o.title then gp_send(pipe, "set title \"{/:Bold %s}\" enhanced", o.title) end
	if o.xlabel then gp_send(pipe, "set xlabel %q", o.xlabel) end
	if o.ylabel then gp_send(pipe, "set ylabel %q", o.ylabel) end
	if o.xrange then gp_send(pipe, "set xrange [%g:%g]", o.xrange[1], o.xrange[2]) end
	if o.yrange then gp_send(pipe, "set yrange [%g:%g]", o.yrange[1], o.yrange[2]) end
	if o.grid then pipe:write("set grid\n") end
	if o.logx then pipe:write("set logscale x\n") end
	if o.logy then pipe:write("set logscale y\n") end
	if o.xformat then gp_send(pipe, "set format x %q", o.xformat) end
	if o.yformat then gp_send(pipe, "set format y %q", o.yformat) end

	if o.key == false then
		pipe:write("unset key\n")
	elseif type(o.key) == "string" then
		gp_send(pipe, "set key %s", o.key)
	end

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
	local font = self._opts.font and string.format(" font %q", self._opts.font) or ""
	pipe:write("set terminal wxt persist" .. font .. "\n")
	self:_emit(pipe)
	pipe:close()
end

function Figure:series()
	return self._series
end

-- fig:save(path, opts?)
--   auto-detects terminal from extension: .png .svg .pdf .eps
--   opts.size = {w, h}  (pixels for raster, pts for vector)
--   opts.terminal = "pngcairo size 1200,800 font 'Arial,12'"  (full override)
function Figure:save(path, opts)
	opts       = opts or {}
	local pipe = gp_open()

	local font = opts.font or self._opts.font or "Arial,11"
	local size = opts.size or self._opts.size or { 1600, 900 }
	local sz   = string.format(" size %d,%d", size[1], size[2])
	local map  = {
		png = string.format("pngcairo%s font %q", sz, font),
		svg = string.format("svg%s font %q", sz, font),
		pdf = string.format("pdfcairo%s font %q", sz, font),
		eps = string.format("epscairo%s font %q", sz, font),
	}

	local term
	if opts.terminal then
		term = opts.terminal
	else
		local ext = (path:match("%.(%a+)$") or "png"):lower()
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

-- gnuplot enhanced-mode greek letters (with enhanced terminal)
M.sym = {
	alpha = "{/Symbol a}",
	beta = "{/Symbol b}",
	gamma = "{/Symbol g}",
	delta = "{/Symbol d}",
	mu = "{/Symbol m}",
	nu = "{/Symbol n}",
	rho = "{/Symbol r}",
	sigma = "{/Symbol s}",
	omega = "{/Symbol w}",
	Omega = "{/Symbol W}",
	phi = "{/Symbol f}",
	psi = "{/Symbol y}",
	eta = "{/Symbol h}",
	tau = "{/Symbol t}",
	pi = "{/Symbol p}",
	Pi = "{/Symbol P}",
	theta = "{/Symbol q}",
	Theta = "{/Symbol Q}",
}

--
-- Colours
--

M.colour = {
	blue   = "#0077bb",
	red    = "#ee3333",
	green  = "#22aa55",
	orange = "#ff8800",
	purple = "#aa33cc",
	teal   = "#009988",
	pink   = "#cc6677",
	grey   = "#888888",
	black  = "#111111",
}

M.palette = {
	M.colour.blue,
	M.colour.red,
	M.colour.green,
	M.colour.orange,
	M.colour.purple,
	M.colour.teal,
	M.colour.pink,
	M.colour.grey,
}

function M.cycler()
	local i = 0
	return function()
		i = (i % #M.palette) + 1
		return M.palette[i]
	end
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
	figure    = {
		args = "opts?",
		ret  = "Figure",
		doc  = "Create a figure; opts: { title, xlabel, ylabel, xrange, yrange, " ..
			"grid, key, logx, logy, font, size, xformat, yformat }",
	},
	series    = {
		args = "xs, ys, opts?",
		ret  = "Series",
		doc  = "Build a series struct explicitly; opts: { title, style, color, lw, pt, ps, dt }",
	},
	sample    = {
		args = "fn, x0, x1, n?",
		ret  = "xs, ys",
		doc  = "Sample fn over [x0,x1] at n+1 points (default 200); returns two arrays",
	},
	write_csv = {
		args = "path, xs_or_series, ys?",
		ret  = "nil",
		doc  = "Write xs/ys or a list of Series structs to a CSV file",
	},
	cycler    = {
		args = "",
		ret  = "fn:()->string",
		doc  = "Return a stateful function that cycles through M.palette colours on each call",
	},
}

M._constants = {
	sym = {
		doc = "Gnuplot enhanced-mode greek letter strings; use inside title/xlabel/ylabel strings",
		values = {
			alpha = { value = '"{/Symbol a}"', doc = "lowercase alpha" },
			beta  = { value = '"{/Symbol b}"', doc = "lowercase beta" },
			gamma = { value = '"{/Symbol g}"', doc = "lowercase gamma" },
			delta = { value = '"{/Symbol d}"', doc = "lowercase delta" },
			mu    = { value = '"{/Symbol m}"', doc = "lowercase mu" },
			nu    = { value = '"{/Symbol n}"', doc = "lowercase nu" },
			rho   = { value = '"{/Symbol r}"', doc = "lowercase rho" },
			sigma = { value = '"{/Symbol s}"', doc = "lowercase sigma" },
			omega = { value = '"{/Symbol w}"', doc = "lowercase omega" },
			Omega = { value = '"{/Symbol W}"', doc = "uppercase Omega" },
			phi   = { value = '"{/Symbol f}"', doc = "lowercase phi" },
			psi   = { value = '"{/Symbol y}"', doc = "lowercase psi" },
			eta   = { value = '"{/Symbol h}"', doc = "lowercase eta" },
			tau   = { value = '"{/Symbol t}"', doc = "lowercase tau" },
			pi    = { value = '"{/Symbol p}"', doc = "lowercase pi" },
			Pi    = { value = '"{/Symbol P}"', doc = "uppercase Pi" },
			theta = { value = '"{/Symbol q}"', doc = "lowercase theta" },
			Theta = { value = '"{/Symbol Q}"', doc = "uppercase Theta" },
		},
	},
	colour = {
		doc = "Named hex colour strings for explicit series colouring",
		values = {
			blue   = { value = '"#0077bb"', doc = "Primary blue" },
			red    = { value = '"#ee3333"', doc = "Primary red" },
			green  = { value = '"#22aa55"', doc = "Primary green" },
			orange = { value = '"#ff8800"', doc = "Warm orange" },
			purple = { value = '"#aa33cc"', doc = "Mid purple" },
			teal   = { value = '"#009988"', doc = "Cool teal" },
			pink   = { value = '"#cc6677"', doc = "Soft pink" },
			grey   = { value = '"#888888"', doc = "Mid grey" },
			black  = { value = '"#111111"', doc = "Near black" },
		},
	},
	palette = {
		doc = "Ordered colour cycle used by cycler(); blue-first, excludes black",
		values = {
			{ value = '"#0077bb"', doc = "1 blue" },
			{ value = '"#ee3333"', doc = "2 red" },
			{ value = '"#22aa55"', doc = "3 green" },
			{ value = '"#ff8800"', doc = "4 orange" },
			{ value = '"#aa33cc"', doc = "5 purple" },
			{ value = '"#009988"', doc = "6 teal" },
			{ value = '"#cc6677"', doc = "7 pink" },
			{ value = '"#888888"', doc = "8 grey" },
		},
	},
}

M._types = {
	Figure = {
		doc         = "Chainable figure builder; holds series list and display options",
		constructor = "M.figure(opts?)",
		kind        = "table",
		methods     = {
			add       = { args = "xs, ys, opts? | series:Series", ret = "Figure", doc = "Append a data series; accepts raw arrays or a Series struct; chainable" },
			show      = { args = "", ret = "nil", doc = "Open a persistent interactive gnuplot window" },
			save      = { args = "path:string, opts?", ret = "nil", doc = "Save to file; terminal inferred from extension; opts: { size, font, terminal }" },
			write_csv = { args = "path:string", ret = "Figure", doc = "Dump all series to CSV; chainable" },
			hline     = { args = "y:number, opts?", ret = "Figure", doc = "Add a horizontal reference line; opts: { lw, color, dt, title }" },
			vline     = { args = "x:number, opts?", ret = "Figure", doc = "Add a vertical reference line; opts: { lw, color, dt, title }" },
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
