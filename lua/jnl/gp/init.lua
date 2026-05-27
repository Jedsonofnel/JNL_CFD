-- jnl/gp/init.lua - Gnuplot driver via popen
-- <jed@nelson> // 2026-05-27

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
-- Small helpers
--

local image_extensions = {
	png = true,
	svg = true,
	pdf = true,
	eps = true,
}

local function path_extension(path)
	return (path:match("%.([A-Za-z0-9]+)$") or ""):lower()
end

local function is_image_extension(ext)
	return image_extensions[ext] == true
end

local function shallow_copy(t)
	local out = {}

	for k, v in pairs(t or {}) do
		out[k] = v
	end

	return out
end

local function numeric_range(values)
	local lo, hi

	for _, v in ipairs(values or {}) do
		if type(v) == "number" then
			lo = lo and math.min(lo, v) or v
			hi = hi and math.max(hi, v) or v
		end
	end

	return lo, hi
end

--
-- Inline data
--

local function write_xy(pipe, xs, ys)
	assert(#xs == #ys, "xs and ys must be the same length")

	for i = 1, #xs do
		pipe:write(string.format("%.10g %.10g\n", xs[i], ys[i]))
	end

	pipe:write("e\n")
end

--
-- Validation
--

local function series_len(s)
	if not s then return 0 end
	if not s.xs or not s.ys then return 0 end
	return math.min(#s.xs, #s.ys)
end

local function validate_series(s, i)
	assert(type(s) == "table", string.format("[jnl.gp] series %d is not a table", i))
	assert(type(s.xs) == "table", string.format("[jnl.gp] series %d has no xs table", i))
	assert(type(s.ys) == "table", string.format("[jnl.gp] series %d has no ys table", i))
	assert(#s.xs == #s.ys, string.format(
		"[jnl.gp] series %d has mismatched xs/ys lengths: %d vs %d",
		i, #s.xs, #s.ys
	))
	assert(#s.xs > 0, string.format(
		"[jnl.gp] no data passed: series %d has zero points",
		i
	))
end

--
-- Series
--

local Series = {}
Series.__index = Series

local function fmt_number(x)
	if type(x) ~= "number" then
		return tostring(x)
	end

	return string.format("%.3g", x)
end

local function fmt_range(xs)
	if not xs or #xs == 0 then
		return "empty"
	end

	local lo, hi = numeric_range(xs)

	if lo == nil then
		return "non-numeric"
	end

	return string.format("[%s, %s]", fmt_number(lo), fmt_number(hi))
end

local function series_label(s)
	if s.title then
		return string.format("%q", s.title)
	end

	return "untitled"
end

function Series:__tostring()
	local kind = self.kind or "xy"
	local n = series_len(self)
	local label = series_label(self)

	if kind == "histogram" then
		return string.format(
			"Series(%s, %s, bins=%d, xrange=%s)",
			kind,
			label,
			n,
			fmt_range(self.xs)
		)
	end

	return string.format(
		"Series(%s, %s, n=%d, style=%s, xrange=%s, yrange=%s)",
		kind,
		label,
		n,
		tostring(self.style or "linespoints"),
		fmt_range(self.xs),
		fmt_range(self.ys)
	)
end

--
-- Series builders
--

function M.series(xs, ys, opts)
	opts = opts or {}

	return setmetatable({
		kind   = opts.kind or "xy",
		xs     = xs,
		ys     = ys,
		title  = opts.title,
		style  = opts.style or "linespoints",
		colour = opts.colour,
		lw     = opts.lw,
		pt     = opts.pt,
		ps     = opts.ps,
		dt     = opts.dt,
		width  = opts.width,
		fill   = opts.fill,
	}, Series)
end

function M.scatter(xs, ys, opts)
	opts = shallow_copy(opts)
	opts.style = opts.style or "points"
	opts.pt = opts.pt or 7
	opts.ps = opts.ps or 0.8

	return M.series(xs, ys, opts)
end

function M.histogram(values, opts)
	opts = opts or {}

	local bins = opts.bins or 10
	if bins < 1 then
		error("histogram: bins must be at least 1")
	end

	local lo = opts.lo
	local hi = opts.hi

	if lo == nil or hi == nil then
		local data_lo, data_hi = numeric_range(values)
		lo = lo or data_lo
		hi = hi or data_hi
	end

	if lo == nil or hi == nil then
		error("histogram: expected at least one numeric value")
	end

	if hi < lo then
		error("histogram: hi must be greater than or equal to lo")
	end

	if hi == lo then
		lo = lo - 0.5
		hi = hi + 0.5
	end

	local width = (hi - lo) / bins
	local centres = {}
	local counts = {}

	for i = 1, bins do
		centres[i] = lo + (i - 0.5) * width
		counts[i] = 0
	end

	for _, v in ipairs(values or {}) do
		if type(v) == "number" then
			local i = math.floor((v - lo) / width) + 1

			if i < 1 then i = 1 end
			if i > bins then i = bins end

			counts[i] = counts[i] + 1
		end
	end

	return setmetatable({
		kind   = "histogram",
		xs     = centres,
		ys     = counts,
		title  = opts.title,
		style  = "boxes",
		colour = opts.colour,
		width  = opts.width or width * 0.9,
		fill   = opts.fill,
	}, Series)
end

local function series_cmd(s)
	local t = { "'-'" }

	if s.kind == "histogram" then
		table.insert(t, "using 1:2 with boxes")
	else
		table.insert(t, "with " .. (s.style or "linespoints"))
	end

	if s.title then
		table.insert(t, string.format("title %q", s.title))
	else
		table.insert(t, "notitle")
	end

	if s.colour then table.insert(t, string.format("lc rgb %q", s.colour)) end
	if s.lw then table.insert(t, "lw " .. s.lw) end
	if s.pt then table.insert(t, "pt " .. s.pt) end
	if s.ps then table.insert(t, "ps " .. s.ps) end
	if s.dt then table.insert(t, "dt " .. s.dt) end

	return table.concat(t, " ")
end

--
-- CSV output
--

local function csv_escape(value)
	if value == nil then
		return ""
	end

	local s = tostring(value)

	if s:find('[,"\n]') then
		s = '"' .. s:gsub('"', '""') .. '"'
	end

	return s
end

local function csv_cell(value)
	if type(value) == "number" then
		return string.format("%.10g", value)
	end

	return csv_escape(value)
end

---Write one or more series to a CSV.
--- - M.write_csv(path, series_list)
--- - M.write_csv(path, xs, ys, header?)
function M.write_csv(path, xs_or_series, ys, header)
	local f = io.open(path, "w")
	if not f then
		error(string.format("[jnl.gp] cannot open %q for writing", path))
	end

	if type(xs_or_series) == "table" and xs_or_series[1] and xs_or_series[1].xs then
		local series_list = xs_or_series
		local heads = {}

		for i, s in ipairs(series_list) do
			local title = s.title or tostring(i)
			table.insert(heads, "x_" .. title)
			table.insert(heads, "y_" .. title)
		end

		f:write(table.concat(heads, ",") .. "\n")

		local nrows = 0
		for _, s in ipairs(series_list) do
			if series_len(s) > nrows then
				nrows = series_len(s)
			end
		end

		for i = 1, nrows do
			local row = {}

			for _, s in ipairs(series_list) do
				table.insert(row, s.xs[i] and csv_cell(s.xs[i]) or "")
				table.insert(row, s.ys[i] and csv_cell(s.ys[i]) or "")
			end

			f:write(table.concat(row, ",") .. "\n")
		end
	else
		local xs = xs_or_series

		assert(#xs == #ys, "xs and ys must be the same length")

		f:write((header or "x,y") .. "\n")

		for i = 1, #xs do
			f:write(csv_cell(xs[i]) .. "," .. csv_cell(ys[i]) .. "\n")
		end
	end

	f:close()
	io.write(string.format("[jnl.gp] csv  -> %s\n", path))
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
		_opts = {
			font    = opts.font or "Arial,11",
			size    = opts.size or { 1600, 900 },
			grid    = opts.grid ~= nil and opts.grid or true,
			title   = opts.title,
			xlabel  = opts.xlabel,
			ylabel  = opts.ylabel,
			xrange  = opts.xrange,
			yrange  = opts.yrange,
			key     = opts.key,
			logx    = opts.logx,
			logy    = opts.logy,
			xformat = opts.xformat,
			yformat = opts.yformat,
		},
	}, Figure)
end

function Figure:validate()
	assert(#self._series > 0, "[jnl.gp] no data passed: figure has no series")

	for i, s in ipairs(self._series) do
		validate_series(s, i)
	end

	return self
end

function Figure:add(xs_or_series, ys, opts)
	if type(xs_or_series) == "table" and xs_or_series.xs then
		table.insert(self._series, xs_or_series)
	else
		table.insert(self._series, M.series(xs_or_series, ys, opts))
	end

	return self
end

function Figure:add_scatter(xs, ys, opts)
	return self:add(M.scatter(xs, ys, opts))
end

function Figure:add_histogram(values, opts)
	return self:add(M.histogram(values, opts))
end

function Figure:hline(y, opts)
	opts = opts or {}

	return self:add(
		{ -1e30, 1e30 },
		{ y, y },
		{
			style = "lines",
			lw = opts.lw or 1,
			colour = opts.colour or "#888888",
			dt = opts.dt or 2,
			title = opts.title,
		}
	)
end

function Figure:vline(x, opts)
	opts = opts or {}

	return self:add(
		{ x, x },
		{ -1e30, 1e30 },
		{
			style = "lines",
			lw = opts.lw or 1,
			colour = opts.colour or "#888888",
			dt = opts.dt or 2,
			title = opts.title,
		}
	)
end

function Figure:series()
	return self._series
end

local function emit_global_series_options(pipe, series_list)
	local histogram_seen = false

	for _, s in ipairs(series_list or {}) do
		if s.kind == "histogram" then
			histogram_seen = true

			if s.width then
				gp_send(pipe, "set boxwidth %g", s.width)
			end
		end
	end

	if histogram_seen then
		pipe:write("set style fill solid 0.6 border\n")
	end
end

function Figure:_emit(pipe)
	local o = self._opts

	gp_send(pipe, "set termoption enhanced")

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

	self:validate()
	emit_global_series_options(pipe, self._series)

	local cmds = {}

	for _, s in ipairs(self._series) do
		table.insert(cmds, series_cmd(s))
	end

	pipe:write("plot " .. table.concat(cmds, ", \\\n     ") .. "\n")

	for _, s in ipairs(self._series) do
		write_xy(pipe, s.xs, s.ys)
	end
end

--
-- Figure output
--

function Figure:show()
	local pipe = gp_open()
	local font = self._opts.font and string.format(" font %q", self._opts.font) or ""

	pipe:write("set terminal wxt persist" .. font .. "\n")
	self:_emit(pipe)
	pipe:close()

	return self
end

function Figure:save(path, opts)
	opts = opts or {}

	local pipe = gp_open()
	local font = opts.font or self._opts.font or "Arial,11"
	local size = opts.size or self._opts.size or { 1600, 900 }
	local sz = string.format(" size %d,%d", size[1], size[2])

	local map = {
		png = string.format("pngcairo%s font %q", sz, font),
		svg = string.format("svg%s font %q", sz, font),
		pdf = string.format("pdfcairo%s font %q", sz, font),
		eps = string.format("epscairo%s font %q", sz, font),
	}

	local term

	if opts.terminal then
		term = opts.terminal
	else
		local ext = path_extension(path)
		term = map[ext] or ("pngcairo" .. sz)
	end

	gp_send(pipe, "set terminal %s", term)
	gp_send(pipe, "set output %q", path)

	self:_emit(pipe)
	pipe:close()

	io.write(string.format("[jnl.gp] saved -> %s\n", path))
	return self
end

function Figure:write(path, opts)
	local ext = path_extension(path)

	if ext == "csv" then
		return self:write_csv(path)
	end

	if is_image_extension(ext) then
		return self:save(path, opts)
	end

	error(string.format(
		"[jnl.gp] unsupported output extension %q for %s; expected .csv, .png, .svg, .pdf, or .eps",
		ext ~= "" and ("." .. ext) or "(none)",
		path
	))
end

function Figure:write_csv(path)
	self:validate()
	M.write_csv(path, self._series)
	return self
end

local function figure_title(fig)
	local title = fig._opts and fig._opts.title
	if title then
		return string.format("%q", title)
	end

	return "untitled"
end

function Figure:__tostring()
	local opts = self._opts or {}
	local parts = {}

	parts[#parts + 1] = string.format("Figure(%s", figure_title(self))
	parts[#parts + 1] = string.format("series=%d", #(self._series or {}))

	if opts.xlabel then
		parts[#parts + 1] = "xlabel=" .. string.format("%q", opts.xlabel)
	end

	if opts.ylabel then
		parts[#parts + 1] = "ylabel=" .. string.format("%q", opts.ylabel)
	end

	if opts.logx then
		parts[#parts + 1] = "logx"
	end

	if opts.logy then
		parts[#parts + 1] = "logy"
	end

	return table.concat(parts, ", ") .. ")"
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
-- Symbols and colours
--

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
	":show() for an interactive window or :write(path) for file output. Extension on " ..
	"the write path selects CSV or image output automatically (.csv .png .svg .pdf .eps). " ..
	"Use M.scatter(xs, ys, opts) and M.histogram(values, opts) for common plotted series."

M._api = {
	figure = {
		args = "opts?",
		ret = "Figure",
		doc =
			"Create a figure; opts: { title, xlabel, ylabel, xrange, yrange, grid, key, " ..
			"logx, logy, font, size, xformat, yformat }",
	},
	series = {
		args = "xs, ys, opts?",
		ret = "Series",
		doc =
		"Build a printable series struct; opts: { kind, title, style, colour, lw, pt, ps, dt, width, fill }",
	},
	scatter = {
		args = "xs, ys, opts?",
		ret = "Series",
		doc = "Build a printable point series; opts are series opts with defaults { style='points', pt=7, ps=0.8 }",
	},
	histogram = {
		args = "values, opts?",
		ret = "Series",
		doc = "Build a printable histogram series; opts: { bins, lo, hi, title, colour, width, fill }",
	},
	sample = {
		args = "fn, x0, x1, n?",
		ret = "xs, ys",
		doc = "Sample fn over [x0,x1] at n+1 points, default 200; returns two arrays",
	},
	write_csv = {
		args = "path, xs_or_series, ys?, header?",
		ret = "nil",
		doc = "Write xs/ys or a list of Series structs to a CSV file",
	},
	cycler = {
		args = "",
		ret = "fn:()->string",
		doc = "Return a stateful function that cycles through M.palette colours on each call",
	},
}

M._constants = {
	sym = {
		doc = "Gnuplot enhanced-mode greek letter strings; use inside title/xlabel/ylabel strings",
		values = {
			alpha = { value = '"{/Symbol a}"', doc = "lowercase alpha" },
			beta = { value = '"{/Symbol b}"', doc = "lowercase beta" },
			gamma = { value = '"{/Symbol g}"', doc = "lowercase gamma" },
			delta = { value = '"{/Symbol d}"', doc = "lowercase delta" },
			mu = { value = '"{/Symbol m}"', doc = "lowercase mu" },
			nu = { value = '"{/Symbol n}"', doc = "lowercase nu" },
			rho = { value = '"{/Symbol r}"', doc = "lowercase rho" },
			sigma = { value = '"{/Symbol s}"', doc = "lowercase sigma" },
			omega = { value = '"{/Symbol w}"', doc = "lowercase omega" },
			Omega = { value = '"{/Symbol W}"', doc = "uppercase Omega" },
			phi = { value = '"{/Symbol f}"', doc = "lowercase phi" },
			psi = { value = '"{/Symbol y}"', doc = "lowercase psi" },
			eta = { value = '"{/Symbol h}"', doc = "lowercase eta" },
			tau = { value = '"{/Symbol t}"', doc = "lowercase tau" },
			pi = { value = '"{/Symbol p}"', doc = "lowercase pi" },
			Pi = { value = '"{/Symbol P}"', doc = "uppercase Pi" },
			theta = { value = '"{/Symbol q}"', doc = "lowercase theta" },
			Theta = { value = '"{/Symbol Q}"', doc = "uppercase Theta" },
		},
	},
	colour = {
		doc = "Named hex colour strings for explicit series colouring",
		values = {
			blue = { value = '"#0077bb"', doc = "Primary blue" },
			red = { value = '"#ee3333"', doc = "Primary red" },
			green = { value = '"#22aa55"', doc = "Primary green" },
			orange = { value = '"#ff8800"', doc = "Warm orange" },
			purple = { value = '"#aa33cc"', doc = "Mid purple" },
			teal = { value = '"#009988"', doc = "Cool teal" },
			pink = { value = '"#cc6677"', doc = "Soft pink" },
			grey = { value = '"#888888"', doc = "Mid grey" },
			black = { value = '"#111111"', doc = "Near black" },
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
		doc = "Chainable figure builder; holds series list and display options",
		constructor = "M.figure(opts?)",
		kind = "table",
		methods = {
			add = {
				args = "xs, ys, opts? | series:Series",
				ret = "Figure",
				doc = "Append a data series; accepts raw arrays or a Series struct; chainable",
			},
			add_scatter = {
				args = "xs, ys, opts?",
				ret = "Figure",
				doc = "Append a scatter series; chainable",
			},
			add_histogram = {
				args = "values, opts?",
				ret = "Figure",
				doc = "Append a histogram series; chainable",
			},
			show = {
				args = "",
				ret = "Figure",
				doc = "Open a persistent interactive gnuplot window",
			},
			write = {
				args = "path:string, opts?",
				ret = "Figure",
				doc =
					"Write figure data or image by extension; .csv dumps series, " ..
					".png/.svg/.pdf/.eps save image output; image opts: { size, font, terminal }",
			},
			save = {
				args = "path:string, opts?",
				ret = "Figure",
				doc = "Save image output; terminal inferred from extension; opts: { size, font, terminal }",
			},
			write_csv = {
				args = "path:string",
				ret = "Figure",
				doc = "Dump all series to CSV; chainable",
			},
			hline = {
				args = "y:number, opts?",
				ret = "Figure",
				doc = "Add a horizontal reference line; opts: { lw, colour, dt, title }",
			},
			vline = {
				args = "x:number, opts?",
				ret = "Figure",
				doc = "Add a vertical reference line; opts: { lw, colour, dt, title }",
			},
			series = {
				args = "",
				ret = "Series[]",
				doc = "Return the figure series list",
			},
			__tostring = {
				args = "self",
				ret = "string",
				doc = "Return a compact REPL summary with title, series count, axis labels, and log-axis flags.",
			},
		},
	},
	Series = {
		doc =
		"Data series descriptor table. Series may represent ordinary xy data, scatter points, or histogram bins.",
		constructor = "M.series(xs, ys, opts?), M.scatter(xs, ys, opts?), or M.histogram(values, opts?)",
		kind = "table",
		methods = {
			__tostring = {
				args = "self",
				ret = "string",
				doc = "Return a compact REPL summary with kind, title, point count, style, and numeric ranges.",
			},
		},
	},
}

return M
