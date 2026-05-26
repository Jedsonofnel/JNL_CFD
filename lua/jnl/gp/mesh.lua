-- lua/jnl/gp/mesh.lua - field extraction helpers for mesh/field data
-- <jed@nelson.ac> // 2026-05-26

local M = {}
M._doc = "Field extraction helpers for plotting mesh field data with jnl.gp."

--
-- Line profile
--

-- Extract field along a line at axis == value.
-- axis: 'x' (vertical slice, returns y coords) or 'y' (horizontal slice, returns x coords)
-- Returns coord_array, field_array sorted along the slice.
-- Warns if no cells found; tolerance defaults to 0.6 * mean_cell_size.
function M.line_profile(mesh, field_vec, axis, value, opts)
	opts = opts or {}
	local tol = opts.tol or mesh:mean_cell_size() * 0.6

	local pts = {}
	for i = 1, mesh:n_cells() do
		local cx, cy  = mesh:cell_centre(i)
		local at, pos = axis == 'x' and cx or cy, axis == 'x' and cy or cx
		if math.abs(at - value) < tol then
			pts[#pts + 1] = { coord = pos, val = field_vec[i] }
		end
	end

	if #pts == 0 then
		io.stderr:write(string.format(
			"[gp.mesh] line_profile: no cells at %s=%.4g (tol=%.4g)\n",
			axis, value, tol))
		return {}, {}
	end

	table.sort(pts, function(a, b) return a.coord < b.coord end)

	local coords, vals = {}, {}
	for _, p in ipairs(pts) do
		coords[#coords + 1] = p.coord
		vals[#vals + 1]     = p.val
	end
	return coords, vals
end

--
-- API
--

M._api = {
	line_profile = {
		args = "mesh:Mesh, field_vec:vec, axis:'x'|'y', value:number, opts:table?",
		ret  = "coords:number[], vals:number[]",
		doc  = "Extract field values along a line slice; opts: { tol }",
	},
}

return M
