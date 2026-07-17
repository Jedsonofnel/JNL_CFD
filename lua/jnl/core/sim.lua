-- jnl/core/sim.lua - general orchestrator to run evented runners
-- <jed@nelson> // 2026-05-23

local Sim = {}
Sim.__index = Sim

--
-- Constructor
--

function Sim.new(runner, alg, opts)
    opts = opts or {}

    local Sage = require("jnl.sage")
    local sage = opts.sage or Sage.new()

    for _, rs in ipairs(alg.rulesets or {}) do
        sage:add_ruleset(rs)
    end

    return setmetatable({
        _runner = runner,
        _sage = sage,
        _done = false,
        _on_iter = opts.on_iter,
    }, Sim)
end

--
-- Private helpers
--

function Sim:_handle_action(action)
    if action.kind == "stop" then
        self._runner:request_stop(action.reason or "sage_stop")
        return
    end

    -- Unknown actions are intentionally ignored here.
    -- Domain wrappers may interpret them elsewhere if needed.
end

function Sim:_handle_iteration_end(event)
    self._sage:assert({
        kind = "iter_end",
        iter = event.iter,
        loop_depth = 1,
    })

    if self._on_iter then
        self._on_iter(event.iter, self._runner)
    end

    for _, action in ipairs(self._sage:pop_actions()) do
        self:_handle_action(action)
    end
end

--
-- Public API
--

-- Advance the simulation by one small runner step.
--
-- Returns true while more work remains.
-- Returns false once the runner has fully completed, including post.
function Sim:step()
    if self._done then
        return false
    end

    local event = self._runner:step()

    if event.kind == "running" then
        return true
    end

    if event.kind == "iteration_end" then
        self:_handle_iteration_end(event)
        return true
    end

    if event.kind == "done" then
        self._done = true
        return false
    end

    error(
        "core sim: unknown runner event kind '" .. tostring(event.kind) .. "'"
    )
end

function Sim:run()
    while self:step() do
    end
end

function Sim:is_done()
    return self._done or self._runner:is_done()
end

function Sim:sage()
    return self._sage
end

return Sim
