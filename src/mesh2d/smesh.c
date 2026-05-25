#include <assert.h>

#include "mesh2d.h"
#include "internal.h"

//
// Structured Mesh Generation (smesh)
//

static u64 smesh_size(u32 nx, u32 ny);

static struct jnl_patches smesh_patches(jnl_arena *arena, u32 nx, u32 ny);

static struct jnl_mesh_topo smesh_topo_gen(jnl_arena *arena, f64 width,
                                           f64 height, u32 nx, u32 ny);

struct jnl_mesh *jnl_smesh_gen(f64 width, f64 height, u32 nx, u32 ny)
{
	u64 size = smesh_size(nx, ny);
	jnl_arena *arena = arena_create(size + size / 2); // 1.5x headroom

	struct jnl_mesh *mesh = ARENA_PUSH_STRUCT_Z(arena, struct jnl_mesh);
	mesh->arena = arena;

	// 1) Create patches and regions for marking in topo
	mesh->patches = smesh_patches(arena, nx, ny);

	struct jnl_region region = (struct jnl_region){
	    .name = "default",
	    .marker = 0,
	};
	mesh->regions = (struct jnl_regions){
	    .n_regions = 1,
	    .data = ARENA_PUSH_STRUCT_Z(arena, struct jnl_region),
	};
	(*mesh->regions.data) = region;

	// 2) Create topology
	mesh->topo = smesh_topo_gen(arena, width, height, nx, ny);
	jnl_mesh2d_topo_sort_faces(&mesh->topo, &mesh->patches, arena);
	jnl_mesh2d_topo_sort_cells(&mesh->topo, &mesh->regions, arena);

	// 3) Then generate geometry and interpolation coefficinets (general)
	mesh->geom = jnl_mesh2d_geom_gen(arena, mesh->topo);
	mesh->interp = jnl_mesh2d_interp_gen(arena, mesh->topo, mesh->geom);

	return mesh;
}

static u64 smesh_size(u32 nx, u32 ny)
{
	u64 size = sizeof(struct jnl_mesh);

	// patches
	size += 4 * sizeof(struct jnl_patch);

	// regions
	size += 1 * sizeof(struct jnl_region);

	// topology
	u32 n_cells = (nx * ny);
	u32 n_faces = (nx + 1) * ny + nx * (ny + 1);
	size += 2 * (nx + 1) * (ny + 1) * sizeof(f64); // points
	size += 2 * n_faces * sizeof(i32);   // face_point, owner, neighbour
	size += 1 * n_faces * sizeof(i32);   // owner
	size += 1 * n_faces * sizeof(i32);   // neighbour
	size += n_cells * sizeof(i32);       // cell_markers
	size += (n_cells + 1) * sizeof(i32); // cell_vertex_start;
	size += (4 * n_cells) * sizeof(i32); // cell_vertex_list;

	// geometry
	size += 5 * n_faces * sizeof(f64);
	size += 3 * n_cells * sizeof(f64);

	// interp
	size += 6 * n_faces * sizeof(f64);

	return size;
}

// patch markers (for consistency)
#define PNORTH (~0)
#define PEAST (~1)
#define PSOUTH (~2)
#define PWEST (~3)

static struct jnl_patches smesh_patches(jnl_arena *arena, u32 nx, u32 ny)
{
	struct jnl_patches patches;
	patches.n_patches = 4;
	patches.data = ARENA_PUSH_ARRAY_Z(arena, struct jnl_patch, 4);

	patches.data[0] = (struct jnl_patch){
	    .name = "north",
	    .n_faces = nx,
	    .marker = 0,
	};
	patches.data[1] = (struct jnl_patch){
	    .name = "east",
	    .n_faces = ny,
	    .marker = 1,
	};
	patches.data[2] = (struct jnl_patch){
	    .name = "south",
	    .n_faces = nx,
	    .marker = 2,
	};
	patches.data[3] = (struct jnl_patch){
	    .name = "west",
	    .n_faces = ny,
	    .marker = 3,
	};

	return patches;
}

static struct jnl_mesh_topo smesh_topo_gen(jnl_arena *arena, f64 width,
                                           f64 height, u32 nx, u32 ny)
{
	u32 n_vertices = (nx + 1) * (ny + 1);
	u32 n_cells = nx * ny;
	u32 n_faces = (nx + 1) * ny + nx * (ny + 1);
	u32 n_bfaces = (2 * nx) + (2 * ny);
	u32 n_ifaces = n_faces - n_bfaces;

	struct jnl_mesh_topo topo = {
	    .n_vertices = n_vertices,
	    .n_cells = n_cells,
	    .n_faces = n_faces,
	    .n_internal_faces = n_ifaces,

	    .vx = ARENA_PUSH_ARRAY_Z(arena, f64, n_vertices),
	    .vy = ARENA_PUSH_ARRAY_Z(arena, f64, n_vertices),
	    .face_vertex = ARENA_PUSH_ARRAY_Z(arena, i32, n_faces * 2),
	    .owner = ARENA_PUSH_ARRAY_Z(arena, i32, n_faces),
	    .neighbour = ARENA_PUSH_ARRAY_Z(arena, i32, n_faces),

	    .cell_vertex_start = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells + 1),
	    .cell_vertex_list = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells * 4),

	    .cell_marker = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells),
	};

	f64 dx = width / (f64)nx, dy = height / (f64)ny;

#define PT(i, j) ((j) * (nx + 1) + (i))
#define CELL(i, j) ((j) * nx + (i))

	for (u32 j = 0; j <= ny; j++) {
		for (u32 i = 0; i <= nx; i++) {
			u32 p = PT(i, j);
			topo.vx[p] = i * dx;
			topo.vy[p] = j * dy;
		}
	}

	// internal faces
	u32 f = 0;
	for (u32 j = 1; j < ny; j++) {
		for (u32 i = 0; i < nx; i++) {
			topo.face_vertex[f * 2] = PT(i, j);
			topo.face_vertex[(f * 2) + 1] = PT(i + 1, j);
			topo.owner[f] = CELL(i, j - 1);
			topo.neighbour[f] = CELL(i, j);
			f++;
		}
	}

	for (u32 i = 1; i < nx; i++) {
		for (u32 j = 0; j < ny; j++) {
			topo.face_vertex[f * 2] = PT(i, j);
			topo.face_vertex[(f * 2) + 1] = PT(i, j + 1);
			topo.owner[f] = CELL(i - 1, j);
			topo.neighbour[f] = CELL(i, j);
			f++;
		}
	}

	// external faces (north -> east -> south -> west)
	for (u32 i = 0; i < nx; i++) { // NORTH (j=ny)
		topo.face_vertex[f * 2] = PT(i, ny);
		topo.face_vertex[(f * 2) + 1] = PT(i + 1, ny);
		topo.owner[f] = CELL(i, ny - 1);
		topo.neighbour[f] = PNORTH;
		f++;
	}

	for (u32 j = 0; j < ny; j++) { // EAST
		topo.face_vertex[f * 2] = PT(nx, j);
		topo.face_vertex[(f * 2) + 1] = PT(nx, j + 1);
		topo.owner[f] = CELL(nx - 1, j);
		topo.neighbour[f] = PEAST;
		f++;
	}

	for (u32 i = 0; i < nx; i++) { // SOUTH (j=0)
		topo.face_vertex[f * 2] = PT(i, 0);
		topo.face_vertex[(f * 2) + 1] = PT(i + 1, 0);
		topo.owner[f] = CELL(i, 0);
		topo.neighbour[f] = PSOUTH;
		f++;
	}

	for (u32 j = 0; j < ny; j++) { // WEST
		topo.face_vertex[f * 2] = PT(0, j);
		topo.face_vertex[(f * 2) + 1] = PT(0, j + 1);
		topo.owner[f] = CELL(0, j);
		topo.neighbour[f] = PWEST;
		f++;
	}

	for (u32 j = 0; j < ny; j++) {
		for (u32 i = 0; i < nx; i++) {
			u32 c = CELL(i, j);
			topo.cell_vertex_start[c] = c * 4;
			topo.cell_vertex_list[c * 4 + 0] = PT(i, j);
			topo.cell_vertex_list[c * 4 + 1] = PT(i + 1, j);
			topo.cell_vertex_list[c * 4 + 2] = PT(i + 1, j + 1);
			topo.cell_vertex_list[c * 4 + 3] = PT(i, j + 1);
		}
	}
	topo.cell_vertex_start[n_cells] = n_cells * 4;

#undef PT
#undef CELL

	return topo;
}

#undef NORTH
#undef EAST
#undef SOUTH
#undef WEST
