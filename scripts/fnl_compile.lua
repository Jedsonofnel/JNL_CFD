local fennel_dst, src = ...
local fennel = dofile(fennel_dst)
local f = assert(io.open(src, "r"))
local code = f:read("a")
f:close()
io.write((fennel.compileString(code, { filename = src })))
io.write("\n")
