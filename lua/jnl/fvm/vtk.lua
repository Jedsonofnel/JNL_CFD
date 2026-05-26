-- jnl/fvm/vtk.lua - VTK output for FVM fields
-- <jed@nelson.ac> // 2026-05-26

local M = {}
M._doc = "Write FVM field data to VTK legacy ASCII unstructured grid files."

local vtk_internal = require("jnl.vtk_internal")

--
-- Writer
--

local Writer = {}
Writer.__index = Writer

function Writer:scalar(name, vec)
	self._w:add_scalar(name, vec)
	return self
end

-- vec may be a {x, y} table or two separate args
function Writer:vector(name, x, y)
	if type(x) == "table" and y == nil then
		self._w:add_vector(name, x[1], x[2])
	else
		self._w:add_vector(name, x, y)
	end
	return self
end

function Writer:write()
	self._w:write()
end

function M.writer(path, mesh)
	return setmetatable({ _w = vtk_internal.new(path, mesh) }, Writer)
end

--
-- Convenience
--

-- scalars: { name = vec, ... }
-- vectors: { name = {x, y}, ... }
function M.write(path, mesh, scalars, vectors)
	local w = M.writer(path, mesh)
	if scalars then
		for name, vec in pairs(scalars) do
			w:scalar(name, vec)
		end
	end
	if vectors then
		for name, xy in pairs(vectors) do
			w:vector(name, xy[1], xy[2])
		end
	end
	w:write()
end

--
-- API
--

M._api = {
	writer = {
		args = "path:string, mesh:Mesh",
		ret  = "Writer",
		doc  = "Create a VTK writer; add fields then call :write().",
	},
	write = {
		args = "path:string, mesh:Mesh, scalars:table?, vectors:table?",
		ret  = "nil",
		doc  = "One-shot write; scalars is {name=vec}, vectors is {name={x,y}}.",
	},
}

M._types = {
	Writer = {
		doc         = "Chainable VTK writer wrapping vtk_internal.",
		constructor = "vtk.writer(path, mesh)",
		methods     = {
			scalar = { args = "self, name:string, vec:vec", ret = "Writer", doc = "Add a scalar field." },
			vector = { args = "self, name:string, x:vec|table, y:vec?", ret = "Writer", doc = "Add a vector field; x may be a {x,y} table." },
			write  = { args = "self", ret = "nil", doc = "Flush all fields to disk." },
		},
	},
}

return M
