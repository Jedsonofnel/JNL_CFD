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
-- Patch profile
--

local function warn(fmt, ...)
	io.stderr:write("[gp.mesh] " .. string.format(fmt, ...) .. "\n")
end

local function sort_by_coord(a, b)
	return a.coord < b.coord
end

local function field_value_at_face(mesh, field_vec, f, field_location)
	if field_location == "cell" then
		local owner0 = mesh:face_owner0(f)
		return field_vec[owner0 + 1]
	end

	if field_location == "face" then
		return field_vec[f + 1]
	end

	error("patch_profile: opts.field_location must be 'cell' or 'face'")
end

local function face_coord(mesh, f, coord)
	local x, y = mesh:face_centre0(f)

	if coord == "x" then
		return x
	end

	if coord == "y" then
		return y
	end

	error("patch_profile: coord must be 'x', 'y', 's', or 'snorm'")
end

local function patch_length(mesh, patch)
	local len = 0.0

	for k = 0, patch.n_faces - 1 do
		local f = patch.start_face + k
		len = len + mesh:face_area0(f)
	end

	return len
end

local function points_to_arrays(pts)
	local coords, vals = {}, {}

	for _, p in ipairs(pts) do
		coords[#coords + 1] = p.coord
		vals[#vals + 1] = p.val
	end

	return coords, vals
end

local function patch_xy_points(mesh, field_vec, patch, coord, field_location)
	local pts = {}

	for k = 0, patch.n_faces - 1 do
		local f = patch.start_face + k

		pts[#pts + 1] = {
			coord = face_coord(mesh, f, coord),
			val = field_value_at_face(mesh, field_vec, f, field_location),
		}
	end

	return pts
end

local function patch_s_points(mesh, field_vec, patch, coord, field_location)
	local len = patch_length(mesh, patch)
	if len == 0.0 then
		return nil, "zero_length"
	end

	local pts = {}
	local s = 0.0

	for k = 0, patch.n_faces - 1 do
		local f = patch.start_face + k
		local ds = mesh:face_area0(f)
		local sf = s + 0.5 * ds

		if coord == "snorm" then
			sf = sf / len
		end

		pts[#pts + 1] = {
			coord = sf,
			val = field_value_at_face(mesh, field_vec, f, field_location),
		}

		s = s + ds
	end

	return pts
end

local function patch_profile_points(mesh, field_vec, patch, coord, field_location)
	if coord == "x" or coord == "y" then
		return patch_xy_points(mesh, field_vec, patch, coord, field_location)
	end

	if coord == "s" or coord == "snorm" then
		return patch_s_points(mesh, field_vec, patch, coord, field_location)
	end

	error("patch_profile: coord must be 'x', 'y', 's', or 'snorm'")
end

local function default_patch_sort(coord)
	return coord == "x" or coord == "y"
end

-- Extract field values on a named boundary patch.
function M.patch_profile(mesh, field_vec, patch_name, coord, opts)
	opts = opts or {}
	coord = coord or "s"

	local patch = mesh:patch_by_name(patch_name)
	if not patch then
		warn("patch_profile: unknown patch '%s'", tostring(patch_name))
		return {}, {}
	end

	if patch.n_faces == 0 then
		warn("patch_profile: no faces on patch '%s'", tostring(patch_name))
		return {}, {}
	end

	local field_location = opts.field_location or "cell"
	local pts, err = patch_profile_points(mesh, field_vec, patch, coord, field_location)

	if err == "zero_length" then
		warn("patch_profile: patch '%s' has zero length", tostring(patch_name))
		return {}, {}
	end

	local do_sort = opts.sort
	if do_sort == nil then
		do_sort = default_patch_sort(coord)
	end

	if do_sort then
		table.sort(pts or {}, sort_by_coord)
	end

	return points_to_arrays(pts)
end

--
-- API
--

M._api = {
	line_profile = {
		args = "mesh:Mesh2D, field_vec:VecUD, axis:'x'|'y', value:number, opts:table?",
		ret  = "coords:number[], vals:number[]",
		doc  = "Extract field values along a line slice; opts: { tol }",
	},

	patch_profile = {
		args = "mesh:Mesh2D, field_vec:VecUD, patch_name:string, coord:'x'|'y'|'s'|'snorm'?, opts:table?",
		ret  = "coords:number[], vals:number[]",
		doc  = "Extract field values along a boundary patch; opts: { field_location = 'cell'|'face', sort = bool }",
	},
}

return M
