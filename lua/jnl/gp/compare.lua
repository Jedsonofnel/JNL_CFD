-- lua/jnl/gp/compare.lua - Comparison plotting helpers for validation profiles
-- <your@email.llm> // 2026-05-26

local gp = require("jnl.gp")

local M = {}

M._doc =
    "Comparison plotting helpers for numerical, analytical, and reference profiles"

M._doc_subsection = "Use jnl.gp.compare for validation plots such as numerical versus analytical "
    .. "profiles. Profiles are plain tables { coord, value, label? }. The helpers return "
    .. "normal gp Figure objects, so callers can use :show(), :save(path), or :write_csv(path)."

local function label(p, fallback)
    return p.label or p.title or fallback
end

local function assert_profile(name, p)
    assert(type(p) == "table", name .. " must be a profile table")
    assert(type(p.coord) == "table", name .. ".coord must be a table")
    assert(type(p.value) == "table", name .. ".value must be a table")
    assert(
        #p.coord == #p.value,
        name .. ".coord and .value must have same length"
    )
end

local function interp_linear(xs, ys, x)
    if x <= xs[1] then
        return ys[1]
    end

    if x >= xs[#xs] then
        return ys[#ys]
    end

    for i = 1, #xs - 1 do
        local x0 = xs[i]
        local x1 = xs[i + 1]

        if x >= x0 and x <= x1 then
            local t = (x - x0) / (x1 - x0)
            return ys[i] * (1.0 - t) + ys[i + 1] * t
        end
    end

    return ys[#ys]
end

function M.profile(coord, value, opts)
    opts = opts or {}

    return {
        coord = coord,
        value = value,
        label = opts.label,
    }
end

function M.figure(numerical, reference, opts)
    opts = opts or {}

    assert_profile("numerical", numerical)
    assert_profile("reference", reference)

    return gp.figure({
        title = opts.title,
        xlabel = opts.xlabel or "x",
        ylabel = opts.ylabel or "value",
        xrange = opts.xrange,
        yrange = opts.yrange,
        grid = opts.grid ~= false,
        key = opts.key,
        logx = opts.logx,
        logy = opts.logy,
    })
        :add(numerical.coord, numerical.value, {
            title = label(numerical, opts.numerical_label or "numerical"),
            style = opts.numerical_style or "points",
            pt = opts.pt,
            ps = opts.ps,
        })
        :add(reference.coord, reference.value, {
            title = label(reference, opts.reference_label or "reference"),
            style = opts.reference_style or "lines",
            lw = opts.lw,
            dt = opts.dt,
        })
end

function M.show(numerical, reference, opts)
    return M.figure(numerical, reference, opts):show()
end

function M.save(path, numerical, reference, opts)
    return M.figure(numerical, reference, opts):save(path, opts and opts.save)
end

function M.sample_at_reference(numerical, reference)
    assert_profile("numerical", numerical)
    assert_profile("reference", reference)

    local coord = {}
    local num = {}
    local ref = {}
    local err = {}

    for i, x in ipairs(reference.coord) do
        local y_num = interp_linear(numerical.coord, numerical.value, x)
        local y_ref = reference.value[i]

        coord[i] = x
        num[i] = y_num
        ref[i] = y_ref
        err[i] = y_num - y_ref
    end

    return {
        coord = coord,
        numerical = num,
        reference = ref,
        error = err,
    }
end

function M.error_norms(comparison)
    local l1 = 0.0
    local l2 = 0.0
    local linf = 0.0
    local n = #comparison.error

    for _, e in ipairs(comparison.error) do
        local a = math.abs(e)

        l1 = l1 + a
        l2 = l2 + e * e

        if a > linf then
            linf = a
        end
    end

    if n == 0 then
        return {
            l1 = 0.0,
            l2 = 0.0,
            linf = 0.0,
        }
    end

    return {
        l1 = l1 / n,
        l2 = math.sqrt(l2 / n),
        linf = linf,
    }
end

function M.write_comparison_csv(path, comparison, opts)
    opts = opts or {}

    local f = assert(io.open(path, "w"))

    local coord_name = opts.coord_name or "coord"
    local numerical_name = opts.numerical_name or "numerical"
    local reference_name = opts.reference_name or "reference"
    local error_name = opts.error_name or "error"

    f:write(table.concat({
        coord_name,
        numerical_name,
        reference_name,
        error_name,
    }, ",") .. "\n")

    for i, x in ipairs(comparison.coord) do
        f:write(
            string.format(
                "%.10g,%.10g,%.10g,%.10g\n",
                x,
                comparison.numerical[i],
                comparison.reference[i],
                comparison.error[i]
            )
        )
    end

    f:close()
    io.write(string.format("[jnl.gp.compare] csv  -> %s\n", path))
end

function M.write_profile_csv(path, numerical, reference, opts)
    local comparison = M.sample_at_reference(numerical, reference)
    M.write_comparison_csv(path, comparison, opts)
    return comparison
end

--
-- API
--

M._api = {
    profile = {
        args = "coord:number[], value:number[], opts:table?",
        ret = "Profile",
        doc = "Build a validation profile table { coord, value, label? }",
    },
    figure = {
        args = "numerical:Profile, reference:Profile, opts:table?",
        ret = "Figure",
        doc = "Create a numerical-versus-reference comparison figure",
    },
    show = {
        args = "numerical:Profile, reference:Profile, opts:table?",
        ret = "nil",
        doc = "Show a numerical-versus-reference comparison in gnuplot",
    },
    save = {
        args = "path:string, numerical:Profile, reference:Profile, opts:table?",
        ret = "nil",
        doc = "Save a numerical-versus-reference comparison figure",
    },
    sample_at_reference = {
        args = "numerical:Profile, reference:Profile",
        ret = "Comparison",
        doc = "Interpolate numerical data onto reference coordinates and compute errors",
    },
    error_norms = {
        args = "comparison:Comparison",
        ret = "table",
        doc = "Return L1, L2, and Linf error norms for a comparison",
    },
    write_comparison_csv = {
        args = "path:string, comparison:Comparison, opts:table?",
        ret = "nil",
        doc = "Write coord, numerical, reference, and error columns to CSV",
    },
    write_profile_csv = {
        args = "path:string, numerical:Profile, reference:Profile, opts:table?",
        ret = "Comparison",
        doc = "Compare two profiles and write the comparison CSV",
    },
}

M._types = {
    Profile = {
        kind = "table",
        constructor = "jnl.gp.compare.profile(coord, value, opts?)",
        doc = "Profile data table for plotting and validation",
        methods = {},
    },
    Comparison = {
        kind = "table",
        constructor = "jnl.gp.compare.sample_at_reference(numerical, reference)",
        doc = "Numerical data sampled at reference coordinates with error columns",
        methods = {},
    },
}

return M
