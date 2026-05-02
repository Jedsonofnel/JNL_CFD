#include "jnl/common.h"
#include "jnl/arena.h"
#include "mesh2d.h"

//
// Structured Mesh Generation (smesh)
//

static u64 smesh_size(u32 nx, u32 ny);

static struct jnl_mesh_boundary smesh_boundary(jnl_arena *arena, u32 nx,
                                               u32 ny);

static struct jnl_mesh_topo smesh_topo_gen(jnl_arena *arena, f64 width,
                                           f64 height, u32 nx, u32 ny);

struct jnl_mesh *jnl_smesh_gen(f64 width, f64 height, u32 nx, u32 ny)
{
	// TODO: figure out the sizing up front (can't be that hard??)
	jnl_arena *arena = arena_create(smesh_size(nx, ny));

	struct jnl_mesh *mesh = ARENA_PUSH_STRUCT_Z(arena, struct jnl_mesh);
	mesh->arena = arena;

	// 1) Create boundaries for marking in topo
	mesh->boundary = smesh_boundary(arena, nx, ny);

	// 2) Create topology
	mesh->topo = smesh_topo_gen(arena, width, height, nx, ny);

	// 3) Then generate geometry and interpolation coefficinets (general)

	return mesh;
}

static u64 smesh_size(u32 nx, u32 ny)
{
	u64 size = sizeof(struct jnl_mesh);

	// boundaries
	size += 4 * sizeof(struct jnl_boundary);

	// topo
	size += 2 * (nx + 1) * (ny + 1) * sizeof(f64); // points

	// geometry

	// interp

	return size;
}

static struct jnl_mesh_boundary smesh_boundary(jnl_arena *arena, u32 nx, u32 ny)
{
	struct jnl_mesh_boundary bounds;
	bounds.n_boundaries = 4;
	bounds.boundaries = ARENA_PUSH_ARRAY_Z(arena, struct jnl_boundary, 4);

	bounds.boundaries[0] = (struct jnl_boundary){
	    .name = "north",
	    .n_faces = nx,
	    .marker = 0,
	};
	bounds.boundaries[1] = (struct jnl_boundary){
	    .name = "east",
	    .n_faces = ny,
	    .marker = 1,
	};
	bounds.boundaries[2] = (struct jnl_boundary){
	    .name = "south",
	    .n_faces = nx,
	    .marker = 2,
	};
	bounds.boundaries[3] = (struct jnl_boundary){
	    .name = "west",
	    .n_faces = ny,
	    .marker = 3,
	};

	return bounds;
}

static struct jnl_mesh_topo smesh_topo_gen(jnl_arena *arena, f64 width,
                                           f64 height, u32 nx, u32 ny)
{
	u32 n_points = (nx + 1) * (ny + 1);
	struct jnl_mesh_topo topo = {
	    .n_points = n_points,
	    .px = ARENA_PUSH_ARRAY_Z(arena, f64, n_points),
	    .py = ARENA_PUSH_ARRAY_Z(arena, f64, n_points),
	    // TODO - the rest
	};

	f64 flx = width / (f64)nx, fly = height / (f64)ny;
	for (u32 i = 0; i < n_points; i++) {
		topo.px[i] = (i % (nx + 1)) * flx;
		topo.py[i] = (u32)(i / (nx + 1)) * fly;
	}

	return topo;
}

//
// Lifecycle
//

void jnl_mesh_free(struct jnl_mesh *mesh)
{
	if (!mesh)
		return;

	jnl_arena *arena = mesh->arena;
	arena_destroy(arena);
}
