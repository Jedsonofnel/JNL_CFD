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
	u32 n_cells = (nx * ny);
	u32 n_faces = (nx + 1) * ny + nx * (ny + 1);
	size += 2 * (nx + 1) * (ny + 1) * sizeof(f64); // points
	size += 4 * n_faces * sizeof(i32);   // face_point, owner, neighbour
	size += (n_cells + 1) * sizeof(i32); // cell_face_start;
	size += (4 * n_cells) * sizeof(i32); // cell_face_point;

	// geometry

	// interp

	return size;
}

// boundary markers (for consistency)
#define NORTH (0)
#define EAST (1)
#define SOUTH (2)
#define WEST (3)

static struct jnl_mesh_boundary smesh_boundary(jnl_arena *arena, u32 nx, u32 ny)
{
	struct jnl_mesh_boundary bounds;
	bounds.n_boundaries = 4;
	bounds.boundaries = ARENA_PUSH_ARRAY_Z(arena, struct jnl_boundary, 4);

	bounds.boundaries[NORTH] = (struct jnl_boundary){
	    .name = "north",
	    .n_faces = nx,
	    .marker = NORTH,
	};
	bounds.boundaries[EAST] = (struct jnl_boundary){
	    .name = "east",
	    .n_faces = ny,
	    .marker = EAST,
	};
	bounds.boundaries[SOUTH] = (struct jnl_boundary){
	    .name = "south",
	    .n_faces = nx,
	    .marker = SOUTH,
	};
	bounds.boundaries[WEST] = (struct jnl_boundary){
	    .name = "west",
	    .n_faces = ny,
	    .marker = WEST,
	};

	return bounds;
}

static struct jnl_mesh_topo smesh_topo_gen(jnl_arena *arena, f64 width,
                                           f64 height, u32 nx, u32 ny)
{
	u32 n_points = (nx + 1) * (ny + 1);
	u32 n_cells = nx * ny;
	u32 n_faces = (nx + 1) * ny + nx * (ny + 1);
	u32 n_bfaces = (2 * nx) + (2 * ny);
	u32 n_ifaces = n_faces - n_bfaces;

	struct jnl_mesh_topo topo = {
	    .n_points = n_points,
	    .n_cells = n_cells,
	    .n_faces = n_faces,
	    .n_internal_faces = n_ifaces,

	    .px = ARENA_PUSH_ARRAY_Z(arena, f64, n_points),
	    .py = ARENA_PUSH_ARRAY_Z(arena, f64, n_points),
	    .face_point = ARENA_PUSH_ARRAY_Z(arena, i32, n_faces * 2),
	    .owner = ARENA_PUSH_ARRAY_Z(arena, i32, n_faces),
	    .neighbour = ARENA_PUSH_ARRAY_Z(arena, i32, n_faces),
	    .cell_face_start = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells + 1),
	    .cell_face_point = ARENA_PUSH_ARRAY_Z(arena, i32, 4 * n_cells),
	};

	f64 dx = width / (f64)nx, dy = height / (f64)ny;

#define PT(i, j) ((j) * (nx + 1) + (i))
#define CELL(i, j) ((j) * nx + (i))

	for (u32 j = 0; j <= ny; j++) {
		for (u32 i = 0; i <= nx; i++) {
			u32 p = PT(i, j);
			topo.px[p] = i * dx;
			topo.py[p] = j * dy;
		}
	}

	// internal faces
	u32 f = 0;
	for (u32 j = 1; j < ny; j++) {
		for (u32 i = 0; i < nx; i++) {
			topo.face_point[f * 2] = PT(i, j);
			topo.face_point[(f * 2) + 1] = PT(i + 1, j);
			topo.owner[f] = CELL(i, j);
			topo.neighbour[f] = CELL(i, j + 1);
			f++;
		}
	}

	for (u32 i = 1; i < nx; i++) {
		for (u32 j = 0; j < ny; j++) {
			topo.face_point[f * 2] = PT(i, j);
			topo.face_point[(f * 2) + 1] = PT(i, j + 1);
			topo.owner[f] = CELL(i, j);
			topo.neighbour[f] = CELL(i + 1, j);
			f++;
		}
	}

	// external faces (north -> east -> south -> west)
	for (u32 i = 0; i < nx; i++) { // NORTH
		topo.face_point[f * 2] = PT(i, 0);
		topo.face_point[(f * 2) + 1] = PT(i + 1, 0);
		topo.owner[f] = CELL(i, 0);
		topo.neighbour[f] = NORTH;
		f++;
	}

	for (u32 j = 0; j <= ny; j++) { // EAST
		topo.face_point[f * 2] = PT(j, nx + 1);
		topo.face_point[(f * 2) + 1] = PT(j + 1, nx + 1);
		topo.owner[f] = CELL(nx, j);
		topo.neighbour[f] = EAST;
		f++;
	}

	for (u32 i = 0; i < nx; i++) { // SOUTH
		topo.face_point[f * 2] = PT(i, ny + 1);
		topo.face_point[(f * 2) + 1] = PT(i + 1, ny + 1);
		topo.owner[f] = CELL(i, ny);
		topo.neighbour[f] = SOUTH;
		f++;
	}

	for (u32 j = 0; j <= ny; j++) { // WEST
		topo.face_point[f * 2] = PT(j, 0);
		topo.face_point[(f * 2) + 1] = PT(j + 1, 0);
		topo.owner[f] = CELL(0, j);
		topo.neighbour[f] = WEST;
		f++;
	}

	for (u32 i = 0; i <= n_cells; i++) {
		topo.cell_face_start[i] = i * 4;
	}

#undef PT
#undef CELL

	return topo;
}

#undef NORTH
#undef EAST
#undef SOUTH
#undef WEST

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
