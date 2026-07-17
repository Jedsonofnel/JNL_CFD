-- jnl/fvm/dispatch_test.lua
-- Dispatch functions take (case, inst) where case is a plain table.
-- B.* calls are patched for policy-routing tests; no C mesh needed.

local h = require("test.harness")
local D = require("jnl.fvm.dispatch")
local B = require("jnl.fvm.bindings")

--
-- Mock builders
--

local function make_field(name)
    local t = { _name = name, _calls = {} }
    function t:fill(v)
        self._calls[#self._calls + 1] = { "fill", v }
    end

    function t:clamp(lo, hi)
        self._calls[#self._calls + 1] = { "clamp", lo, hi }
    end

    function t:axpy(a, _)
        self._calls[#self._calls + 1] = { "axpy", a }
    end

    function t:copy_from(_)
        self._calls[#self._calls + 1] = { "copy_from" }
    end

    function t:norm_l2()
        return 0.0
    end

    return t
end

local function make_sys(name)
    local t = { _name = name, _calls = {} }
    function t:reset()
        self._calls[#self._calls + 1] = { "reset" }
    end

    function t:under_relax(_, a)
        self._calls[#self._calls + 1] = { "under_relax", a }
    end

    return t
end

-- cfg that returns a fixed value for every key
local function make_cfg(overrides)
    local DEFAULTS = {
        grad = "gg",
        div = "uds",
        non_ortho = true,
        relax = 0.7,
        tvd_limiter = "minmod",
    }
    return {
        get = function(_, _, key)
            if overrides and overrides[key] ~= nil then
                return overrides[key]
            end
            return DEFAULTS[key]
        end,
    }
end

local function make_case(fields, systems, cfg_overrides, exec_overrides)
    local field_map = {}
    local sys_map = {}
    for k, v in pairs(fields or {}) do
        field_map[k] = v
    end
    for k, v in pairs(systems or {}) do
        sys_map[k] = v
    end
    return {
        field_map = field_map,
        sys_map = sys_map,
        mesh = nil, -- not needed for pure logic tests
        cell_pool = nil,
        face_pool = nil,
        exec = setmetatable(exec_overrides or {}, {
            __index = { dt = nil, coeff = nil },
        }),
        cfg = make_cfg(cfg_overrides),
        bindings = {},
        compiled = {
            reg = {
                entry = function()
                    return nil
                end,
            },
        },
    }
end

-- Temporarily replace a B function, call fn(), restore.
local function with_mock_B(name, mock, fn)
    local orig = B[name]
    B[name] = mock
    local ok, err = pcall(fn)
    B[name] = orig
    if not ok then
        error(err, 2)
    end
end

-- Collect calls to a named B function during fn().
local function capture_B(name, fn)
    local calls = {}
    with_mock_B(name, function(...)
        calls[#calls + 1] = { ... }
    end, fn)
    return calls
end

--
-- Infrastructure ops
--

h.describe("dispatch: comment", function()
    h.it("is a no-op, does not error", function()
        h.expect(function()
            D.comment(nil, { op = "comment", text = "hi" })
        end).not_throws()
    end)
end)

h.describe("dispatch: fill / zero / clip", function()
    h.it("fill calls field:fill with inst.value", function()
        local f = make_field("phi")
        local case = make_case({ phi = f })
        D.fill(case, { field = "phi", value = 3.14 })
        h.expect(f._calls[1][1]).equals("fill")
        h.expect(f._calls[1][2]).equals(3.14)
    end)

    h.it("fill defaults to 0 when value is absent", function()
        local f = make_field("phi")
        local case = make_case({ phi = f })
        D.fill(case, { field = "phi" })
        h.expect(f._calls[1][2]).equals(0.0)
    end)

    h.it("zero calls field:fill(0)", function()
        local f = make_field("phi")
        local case = make_case({ phi = f })
        D.zero(case, { field = "phi" })
        h.expect(f._calls[1][1]).equals("fill")
        h.expect(f._calls[1][2]).equals(0.0)
    end)

    h.it("clip calls field:clamp with lo and hi", function()
        local f = make_field("phi")
        local case = make_case({ phi = f })
        D.clip(case, { field = "phi", lo = 0.0, hi = 1.0 })
        h.expect(f._calls[1][1]).equals("clamp")
        h.expect(f._calls[1][2]).equals(0.0)
        h.expect(f._calls[1][3]).equals(1.0)
    end)
end)

h.describe("dispatch: sys_reset", function()
    h.it("calls sys:reset()", function()
        local s = make_sys("p")
        local case = make_case({}, { p = s })
        D.sys_reset(case, { field = "p" })
        h.expect(s._calls[1][1]).equals("reset")
    end)
end)

h.describe("dispatch: under_relax", function()
    h.it("reads alpha from cfg and passes to sys:under_relax", function()
        local f = make_field("p")
        local s = make_sys("p")
        local case = make_case({ p = f }, { p = s }, { relax = 0.3 })

        with_mock_B("laplacian_k", function() end, function()
            -- under_relax calls sys:under_relax directly (not via B)
            D.under_relax(case, { field = "p" })
        end)

        h.expect(s._calls[1][1]).equals("under_relax")
        h.expect(s._calls[1][2]).equals(0.3)
    end)
end)

h.describe("dispatch: abstract ops are silent no-ops", function()
    h.it("evaluate does nothing", function()
        h.expect(function()
            D.evaluate(make_case(), { field = "phi", op = "evaluate" })
        end).not_throws()
    end)

    h.it("solve does nothing", function()
        h.expect(function()
            D.solve(make_case(), { field = "phi", op = "solve" })
        end).not_throws()
    end)

    h.it("correct does nothing", function()
        h.expect(function()
            D.correct(make_case(), { field = "phi", op = "correct" })
        end).not_throws()
    end)
end)

--
-- DDT no-op policy
--

h.describe("dispatch: ddt_k no-op when exec.dt is nil", function()
    h.it("does not call B.ddt_k when dt is nil", function()
        local s = make_sys("phi")
        local prev = make_field("prev_phi")
        local case = make_case(
            { ["prev_phi"] = prev },
            { phi = s },
            nil,
            { dt = nil }
        )

        local calls = capture_B("ddt_k", function()
            D.ddt_k(case, { field = "phi", coeff = 1.0 })
        end)
        h.expect(#calls).equals(0)
    end)

    h.it("does not call B.ddt_f when dt is nil", function()
        local s = make_sys("phi")
        local prev = make_field("prev_phi")
        local case = make_case(
            { ["prev_phi"] = prev },
            { phi = s },
            nil,
            { dt = nil }
        )

        local calls = capture_B("ddt_f", function()
            D.ddt_f(case, { field = "phi", coeff = "rho" })
        end)
        h.expect(#calls).equals(0)
    end)
end)

--
-- Non-ortho correction policy
--

h.describe("dispatch: lap_nonorth no-op when non_ortho=false", function()
    h.it("lap_nonorth_k does not call B when non_ortho=false", function()
        local s = make_sys("phi")
        local gx = make_field("grad_phi_x")
        local gy = make_field("grad_phi_y")
        local case = make_case(
            { grad_phi_x = gx, grad_phi_y = gy },
            { phi = s },
            { non_ortho = false }
        )

        local calls = capture_B("laplacian_nonorth_k", function()
            D.lap_nonorth_k(case, {
                field = "phi",
                coeff = 1.0,
                grad_x = "grad_phi_x",
                grad_y = "grad_phi_y",
            })
        end)
        h.expect(#calls).equals(0)
    end)

    h.it("lap_nonorth_k calls B when non_ortho=true", function()
        local s = make_sys("phi")
        local gx = make_field("grad_phi_x")
        local gy = make_field("grad_phi_y")
        local case = make_case(
            { grad_phi_x = gx, grad_phi_y = gy },
            { phi = s },
            { non_ortho = true }
        )

        local calls = capture_B("laplacian_nonorth_k", function()
            D.lap_nonorth_k(case, {
                field = "phi",
                coeff = 1.0,
                grad_x = "grad_phi_x",
                grad_y = "grad_phi_y",
            })
        end)
        h.expect(#calls).equals(1)
    end)
end)

--
-- Convection scheme policy
--

h.describe("dispatch: div_k scheme routing", function()
    local function test_scheme(scheme)
        local s = make_sys("phi")
        local un = make_field("mwi_U_p")
        local case = make_case(
            { ["mwi_U_p"] = un },
            { phi = s },
            { div = scheme }
        )
        local got = {}

        with_mock_B("div_uds_k", function()
            got[#got + 1] = "div_uds_k"
        end, function()
            with_mock_B("div_cds_k", function()
                got[#got + 1] = "div_cds_k"
            end, function()
                D.div_k(case, { field = "phi", coeff = 1.0, flux = "mwi_U_p" })
            end)
        end)
        return got[1]
    end

    h.it("uds scheme routes to B.div_uds_k", function()
        h.expect(test_scheme("uds")).equals("div_uds_k")
    end)

    h.it("cds scheme routes to B.div_cds_k", function()
        h.expect(test_scheme("cds")).equals("div_cds_k")
    end)

    h.it("tvd scheme routes to B.div_uds_k as implicit base", function()
        h.expect(test_scheme("tvd")).equals("div_uds_k")
    end)
end)

h.describe("dispatch: div_dc no-op for non-tvd schemes", function()
    local function run_div_dc(scheme)
        local s = make_sys("phi")
        local un = make_field("mwi_U_p")
        local phi = make_field("phi")
        local gx = make_field("grad_phi_x")
        local gy = make_field("grad_phi_y")
        local case = make_case(
            { phi = phi, ["mwi_U_p"] = un, grad_phi_x = gx, grad_phi_y = gy },
            { phi = s },
            { div = scheme }
        )

        local calls = {}
        local function mock_tvd()
            calls[#calls + 1] = "tvd"
        end
        with_mock_B("div_tvd_minmod", mock_tvd, function()
            with_mock_B("div_tvd_van_leer", mock_tvd, function()
                with_mock_B("div_tvd_superbee", mock_tvd, function()
                    D.div_dc(case, {
                        field = "phi",
                        flux = "mwi_U_p",
                        grad_x = "grad_phi_x",
                        grad_y = "grad_phi_y",
                    })
                end)
            end)
        end)
        return calls
    end

    h.it("no B call for uds", function()
        h.expect(#run_div_dc("uds")).equals(0)
    end)

    h.it("no B call for cds", function()
        h.expect(#run_div_dc("cds")).equals(0)
    end)

    h.it("calls B.div_tvd_minmod for tvd with default limiter", function()
        h.expect(#run_div_dc("tvd")).equals(1)
        h.expect(run_div_dc("tvd")[1]).equals("tvd")
    end)
end)

h.describe("dispatch: div_dc tvd limiter routing", function()
    local function limiter_fn(limiter)
        local s = make_sys("phi")
        local phi = make_field("phi")
        local un = make_field("mwi_U_p")
        local gx = make_field("grad_phi_x")
        local gy = make_field("grad_phi_y")
        local case = make_case(
            { phi = phi, ["mwi_U_p"] = un, grad_phi_x = gx, grad_phi_y = gy },
            { phi = s },
            { div = "tvd", tvd_limiter = limiter }
        )

        local called = {}
        with_mock_B("div_tvd_minmod", function()
            called[#called + 1] = "minmod"
        end, function()
            with_mock_B("div_tvd_van_leer", function()
                called[#called + 1] = "van_leer"
            end, function()
                with_mock_B("div_tvd_superbee", function()
                    called[#called + 1] = "superbee"
                end, function()
                    D.div_dc(case, {
                        field = "phi",
                        flux = "mwi_U_p",
                        grad_x = "grad_phi_x",
                        grad_y = "grad_phi_y",
                    })
                end)
            end)
        end)
        return called[1]
    end

    h.it("minmod limiter calls B.div_tvd_minmod", function()
        h.expect(limiter_fn("minmod")).equals("minmod")
    end)

    h.it("van_leer limiter calls B.div_tvd_van_leer", function()
        h.expect(limiter_fn("van_leer")).equals("van_leer")
    end)

    h.it("superbee limiter calls B.div_tvd_superbee", function()
        h.expect(limiter_fn("superbee")).equals("superbee")
    end)
end)

--
-- Source term volumetric/integrated routing
--

h.describe("dispatch: su_k volumetric vs integrated routing", function()
    local function run_su_k(volumetric)
        local s = make_sys("phi")
        local case = make_case({}, { phi = s })
        local called = {}
        with_mock_B("su_v_k", function()
            called[#called + 1] = "v_k"
        end, function()
            with_mock_B("su_i_k", function()
                called[#called + 1] = "i_k"
            end, function()
                D.su_k(
                    case,
                    { field = "phi", coeff = 1.0, volumetric = volumetric }
                )
            end)
        end)
        return called[1]
    end

    h.it("volumetric=true routes to B.su_v_k", function()
        h.expect(run_su_k(true)).equals("v_k")
    end)

    h.it("volumetric=false routes to B.su_i_k", function()
        h.expect(run_su_k(false)).equals("i_k")
    end)
end)

--
-- Missing field errors
--

h.describe("dispatch: field errors on unknown name", function()
    h.it("fill throws on unknown field", function()
        local case = make_case({})
        h.expect(function()
            D.fill(case, { field = "nonexistent", value = 0 })
        end).throws("nonexistent")
    end)

    h.it("sys_reset throws on unknown system", function()
        local case = make_case({}, {})
        h.expect(function()
            D.sys_reset(case, { field = "nonexistent" })
        end).throws("nonexistent")
    end)
end)
