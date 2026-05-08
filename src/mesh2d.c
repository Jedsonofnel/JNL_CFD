#include <math.h>
#include <string.h>
#include <assert.h>

#include "jnl/common.h"
#include "jnl/arena.h"
#include "mesh2d.h"

//
// General reusable helpers
//

// topology helpers

static enum jnl_mesh_err topo_sort_faces(struct jnl_mesh_topo *,
                                         struct jnl_patches *, jnl_arena *);

static enum jnl_mesh_err topo_sort_cells(struct jnl_mesh_topo *,
                                         struct jnl_regions *, jnl_arena *);

static void build_cell_faces(struct jnl_mesh_topo *, jnl_arena *);

// generators for the rest

static struct jnl_mesh_geom geom_gen(jnl_arena *, struct jnl_mesh_topo);
static struct jnl_mesh_interp interp_gen(jnl_arena *, struct jnl_mesh_topo,
                                         struct jnl_mesh_geom);

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
	topo_sort_faces(&mesh->topo, &mesh->patches, arena);
	topo_sort_cells(&mesh->topo, &mesh->regions, arena);
	build_cell_faces(&mesh->topo, arena);

	// 3) Then generate geometry and interpolation coefficinets (general)
	mesh->geom = geom_gen(arena, mesh->topo);
	mesh->interp = interp_gen(arena, mesh->topo, mesh->geom);

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
	size += (n_cells + 1) * sizeof(i32); // cell_face_start;
	size += (4 * n_cells) * sizeof(i32); // cell_face_list;

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

	    .cell_marker = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells),
	    // cell_face_* stuff handled by build_cell_faces()
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
			topo.owner[f] = CELL(i - 1, j);
			topo.neighbour[f] = CELL(i, j);
			f++;
		}
	}

	// external faces (north -> east -> south -> west)
	for (u32 i = 0; i < nx; i++) { // NORTH (j=ny)
		topo.face_point[f * 2] = PT(i, ny);
		topo.face_point[(f * 2) + 1] = PT(i + 1, ny);
		topo.owner[f] = CELL(i, ny - 1);
		topo.neighbour[f] = PNORTH;
		f++;
	}

	for (u32 j = 0; j < ny; j++) { // EAST
		topo.face_point[f * 2] = PT(nx, j);
		topo.face_point[(f * 2) + 1] = PT(nx, j + 1);
		topo.owner[f] = CELL(nx - 1, j);
		topo.neighbour[f] = PEAST;
		f++;
	}

	for (u32 i = 0; i < nx; i++) { // SOUTH (j=0)
		topo.face_point[f * 2] = PT(i, 0);
		topo.face_point[(f * 2) + 1] = PT(i + 1, 0);
		topo.owner[f] = CELL(i, 0);
		topo.neighbour[f] = PSOUTH;
		f++;
	}

	for (u32 j = 0; j < ny; j++) { // WEST
		topo.face_point[f * 2] = PT(0, j);
		topo.face_point[(f * 2) + 1] = PT(0, j + 1);
		topo.owner[f] = CELL(0, j);
		topo.neighbour[f] = PWEST;
		f++;
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
// Reusable helpers for generating from topology faces
//

static enum jnl_mesh_err topo_sort_faces(struct jnl_mesh_topo *topo,
                                         struct jnl_patches *patches,
                                         jnl_arena *arena)
{
	i32 n = topo->n_faces;

	// Build permutation
	u64 scratch_pos = arena->pos;
	i32 *perm = ARENA_PUSH_ARRAY(arena, i32, n);
	i32 *tmp_fp = ARENA_PUSH_ARRAY(arena, i32, n * 2);
	i32 *tmp_own = ARENA_PUSH_ARRAY(arena, i32, n);
	i32 *tmp_nb = ARENA_PUSH_ARRAY(arena, i32, n);

	// Partition: internal first, then boundary sorted by ~neighbour (marker)
	i32 ipos = 0;
	i32 bpos = 0;

	// Count internals to know where boundary block starts
	i32 n_internal = topo->n_internal_faces;
	ipos = 0;
	bpos = n_internal;

	// Validate every boundary face has a neighbour that decodes to a known
	// patch marker
	for (i32 f = 0; f < n; f++) {
		if (topo->neighbour[f] < 0) {
			i32 marker = ~topo->neighbour[f];
			bool found = false;
			for (i32 p = 0; p < patches->n_patches; p++) {
				if (patches->data[p].marker == marker) {
					found = true;
					break;
				}
			}
			if (!found)
				return JNL_MESH_ERR_UNKNOWN_PATCH;
		}
	}

	for (i32 f = 0; f < n; f++) {
		if (topo->neighbour[f] >= 0) {
			perm[ipos++] = f;
		} else {
			perm[bpos++] = f;
		}
	}

	// Stable sort boundary section by marker (~neighbour), ascending.
	// Insertion sort is fine: boundary count is small
	i32 nb_count = n - n_internal;
	i32 *bsec = perm + n_internal;
	for (i32 i = 1; i < nb_count; i++) {
		i32 key = bsec[i];
		i32 key_m = ~topo->neighbour[key]; // decode marker
		i32 j = i - 1;
		while (j >= 0 && ~topo->neighbour[bsec[j]] > key_m) {
			bsec[j + 1] = bsec[j];
			j--;
		}
		bsec[j + 1] = key;
	}

	// Apply permutation to face-parallel arrays
	for (i32 f = 0; f < n; f++) {
		i32 src = perm[f];
		tmp_fp[f * 2] = topo->face_point[src * 2];
		tmp_fp[f * 2 + 1] = topo->face_point[src * 2 + 1];
		tmp_own[f] = topo->owner[src];
		tmp_nb[f] = topo->neighbour[src];
	}
	memcpy(topo->face_point, tmp_fp, n * 2 * sizeof(i32));
	memcpy(topo->owner, tmp_own, n * sizeof(i32));
	memcpy(topo->neighbour, tmp_nb, n * sizeof(i32));

	// Populate boundary start_face by scanning sorted boundary block
	for (i32 p = 0; p < patches->n_patches; p++) {
		i32 marker = patches->data[p].marker;
		i32 encoded = ~marker;

		// Find first face in boundary block with this marker
		for (i32 f = n_internal; f < n; f++) {
			if (topo->neighbour[f] == encoded) {
				patches->data[p].start_face = f;
				break;
			}
		}
	}

	arena_pop_to(arena, scratch_pos);

	return JNL_MESH_OK;
}

static enum jnl_mesh_err topo_sort_cells(struct jnl_mesh_topo *topo,
                                         struct jnl_regions *regions,
                                         jnl_arena *arena)
{
	i32 n_cells = topo->n_cells;
	i32 n_faces = topo->n_faces;

	// Validate: every cell_marker must map to a known region
	for (i32 c = 0; c < n_cells; c++) {
		i32 m = topo->cell_marker[c];
		bool found = false;
		for (i32 r = 0; r < regions->n_regions; r++) {
			if (regions->data[r].marker == m) {
				found = true;
				break;
			}
		}
		if (!found)
			return JNL_MESH_ERR_UNKNOWN_REGION;
	}

	u64 scratch_pos = arena->pos;
	i32 *new_index = ARENA_PUSH_ARRAY(arena, i32, n_cells);
	i32 *cursor = ARENA_PUSH_ARRAY_Z(arena, i32, regions->n_regions);

	// Count cells per region
	for (i32 c = 0; c < n_cells; c++) {
		i32 m = topo->cell_marker[c];
		for (i32 r = 0; r < regions->n_regions; r++) {
			if (regions->data[r].marker == m) {
				cursor[r]++;
				break;
			}
		}
	}

	// Set start_cell and n_cells, reuse cursor as write head
	i32 pos = 0;
	for (i32 r = 0; r < regions->n_regions; r++) {
		regions->data[r].start_cell = pos;
		regions->data[r].n_cells = cursor[r];
		cursor[r] = pos; // write head starts at block start
		pos += regions->data[r].n_cells;
	}

	// Build new_index[old] = new
	for (i32 c = 0; c < n_cells; c++) {
		i32 m = topo->cell_marker[c];
		for (i32 r = 0; r < regions->n_regions; r++) {
			if (regions->data[r].marker == m) {
				new_index[c] = cursor[r]++;
				break;
			}
		}
	}

	// Permute cell_marker to match new ordering (scratch on top)
	i32 *tmp_marker = ARENA_PUSH_ARRAY(arena, i32, n_cells);
	for (i32 c = 0; c < n_cells; c++)
		tmp_marker[new_index[c]] = topo->cell_marker[c];
	memcpy(topo->cell_marker, tmp_marker, n_cells * sizeof(i32));

	// Update owner/neighbour to new cell indices
	for (i32 f = 0; f < n_faces; f++) {
		topo->owner[f] = new_index[topo->owner[f]];
		if (topo->neighbour[f] >= 0)
			topo->neighbour[f] = new_index[topo->neighbour[f]];
	}

	// cell_face_start/list are now stale
	topo->cell_face_start = NULL;
	topo->cell_face_list = NULL;

	arena_pop_to(arena, scratch_pos);
	return JNL_MESH_OK;
}

static void build_cell_faces(struct jnl_mesh_topo *topo, jnl_arena *arena)
{
	i32 n_cells = topo->n_cells;
	i32 n_faces = topo->n_faces;

	// count faces per cell
	i32 *count = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells);
	for (i32 f = 0; f < n_faces; f++) {
		count[topo->owner[f]]++;
		if (topo->neighbour[f] >= 0) {
			count[topo->neighbour[f]]++;
		}
	}

	// build CSR cell_face_start array
	topo->cell_face_start = ARENA_PUSH_ARRAY(arena, i32, n_cells + 1);
	topo->cell_face_start[0] = 0;
	for (i32 c = 0; c < n_cells; c++) {
		topo->cell_face_start[c + 1] = topo->cell_face_start[c] + count[c];
	}

	// Fill face list and reset count to use as cursor
	i32 total = topo->cell_face_start[n_cells];
	topo->cell_face_list = ARENA_PUSH_ARRAY(arena, i32, total);
	memset(count, 0, n_cells * sizeof(i32));

	for (i32 f = 0; f < n_faces; f++) {
		i32 o = topo->owner[f];
		topo->cell_face_list[topo->cell_face_start[o] + count[o]++] = f;
		if (topo->neighbour[f] >= 0) {
			i32 nb = topo->neighbour[f];
			topo->cell_face_list[topo->cell_face_start[nb] + count[nb]++] = f;
		}
	}
}

static struct jnl_mesh_geom geom_gen(jnl_arena *arena,
                                     struct jnl_mesh_topo topo)
{
	i32 n_faces = topo.n_faces;
	i32 n_cells = topo.n_cells;

	struct jnl_mesh_geom geom = {
	    .face_cx = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_cy = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_nx = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_ny = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_area = ARENA_PUSH_ARRAY(arena, f64, n_faces),
	    .cell_cx = ARENA_PUSH_ARRAY(arena, f64, n_cells),
	    .cell_cy = ARENA_PUSH_ARRAY(arena, f64, n_cells),
	    .cell_vol = ARENA_PUSH_ARRAY(arena, f64, n_cells),
	};

	for (u32 f = 0; f < n_faces; f++) {
		i32 p0 = topo.face_point[f * 2];
		i32 p1 = topo.face_point[f * 2 + 1];
		f64 x0 = topo.px[p0], y0 = topo.py[p0];
		f64 x1 = topo.px[p1], y1 = topo.py[p1];

		geom.face_cx[f] = 0.5 * (x0 + x1);
		geom.face_cy[f] = 0.5 * (y0 + y1);

		f64 dx = x1 - x0, dy = y1 - y0;
		f64 len = sqrt(dx * dx + dy * dy);
		geom.face_area[f] = len;

		// rotate 90 degrees "left" of edge direction for normal
		geom.face_nx[f] = dy / len;
		geom.face_ny[f] = -dx / len;
	}

	// Cell quantities via shoelace over faces
	u64 scratch_pos = arena->pos;
	f64 *sum_cx = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells); // scratch
	f64 *sum_cy = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells);

	for (i32 f = 0; f < n_faces; f++) {
		i32 p0 = topo.face_point[f * 2];
		i32 p1 = topo.face_point[f * 2 + 1];
		f64 x0 = topo.px[p0], y0 = topo.py[p0];
		f64 x1 = topo.px[p1], y1 = topo.py[p1];

		// Shoelace cross term and centroid weight for p0->p1
		f64 cross = x0 * y1 - x1 * y0;
		f64 wx = (x0 + x1) * cross;
		f64 wy = (y0 + y1) * cross;

		// Owner: p0->p1 (positive contribution)
		i32 o = topo.owner[f];
		geom.cell_vol[o] += cross;
		sum_cx[o] += wx;
		sum_cy[o] += wy;

		// Neighbour: p1->p0 (negated — reverse winding)
		i32 nb = topo.neighbour[f];
		if (nb >= 0) {
			geom.cell_vol[nb] -= cross;
			sum_cx[nb] -= wx;
			sum_cy[nb] -= wy;
		}
	}

	for (i32 c = 0; c < n_cells; c++) {
		for (i32 c = 0; c < n_cells; c++) {
			f64 signed_2a = geom.cell_vol[c];
			assert(signed_2a > 0.0 &&
			       "cell faces must be wound CCW around owner");
			geom.cell_vol[c] =
			    0.5 * signed_2a; // no fabs needed if assert holds
			f64 inv = 1.0 / (3.0 * signed_2a);
			geom.cell_cx[c] = sum_cx[c] * inv;
			geom.cell_cy[c] = sum_cy[c] * inv;
		}
	}

	// Fix face normal signs to point owner->neighbour
	for (i32 f = 0; f < n_faces; f++) {
		i32 o = topo.owner[f];
		f64 dfx = geom.face_cx[f] - geom.cell_cx[o];
		f64 dfy = geom.face_cy[f] - geom.cell_cy[o];

		// If normal points away from owner centre, flip it
		if (dfx * geom.face_nx[f] + dfy * geom.face_ny[f] < 0.0) {
			geom.face_nx[f] = -geom.face_nx[f];
			geom.face_ny[f] = -geom.face_ny[f];
		}
	}

	// remove scratch arrays
	arena_pop_to(arena, scratch_pos);

	return geom;
}

static struct jnl_mesh_interp interp_gen(jnl_arena *arena,
                                         struct jnl_mesh_topo topo,
                                         struct jnl_mesh_geom geom)
{
	i32 n_faces = topo.n_faces;

	struct jnl_mesh_interp interp = {
	    .weight = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .delta_coeff = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .corr_x = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .corr_y = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .skew_x = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .skew_y = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	};

	for (i32 f = 0; f < n_faces; f++) {
		i32 o = topo.owner[f];
		i32 nb = topo.neighbour[f];

		f64 fcx = geom.face_cx[f], fcy = geom.face_cy[f];
		f64 ocx = geom.cell_cx[o], ocy = geom.cell_cy[o];
		f64 nx = geom.face_nx[f], ny = geom.face_ny[f];

		if (nb < 0) {
			interp.weight[f] = 1.0;
			f64 dox = fcx - ocx, doy = fcy - ocy;
			f64 proj = dox * nx + doy * ny;
			interp.delta_coeff[f] = (fabs(proj) > 1e-14) ? 1.0 / proj : 0.0;
			interp.corr_x[f] = 0.0;
			interp.corr_y[f] = 0.0;
			interp.skew_x[f] = 0.0;
			interp.skew_y[f] = 0.0;
		} else {
			f64 ncx = geom.cell_cx[nb], ncy = geom.cell_cy[nb];
			f64 dx = ncx - ocx, dy = ncy - ocy;

			f64 do_dist =
			    sqrt((fcx - ocx) * (fcx - ocx) + (fcy - ocy) * (fcy - ocy));
			f64 dn_dist =
			    sqrt((fcx - ncx) * (fcx - ncx) + (fcy - ncy) * (fcy - ncy));
			f64 d_dist = do_dist + dn_dist;

			f64 w = (d_dist > 1e-14) ? dn_dist / d_dist : 0.5;
			interp.weight[f] = w;

			f64 proj = dx * nx + dy * ny;
			interp.delta_coeff[f] = (fabs(proj) > 1e-14) ? 1.0 / proj : 0.0;

			// non-orthogonality correction: component of d perpendicular to
			// normal
			f64 d_dot_n = dx * nx + dy * ny;
			interp.corr_x[f] = dx - d_dot_n * nx;
			interp.corr_y[f] = dy - d_dot_n * ny;

			// skewness: face centre minus interpolated point on O-N line
			f64 ipx = ocx + w * dx, ipy = ocy + w * dy;
			interp.skew_x[f] = fcx - ipx;
			interp.skew_y[f] = fcy - ipy;
		}
	}

	return interp;
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
