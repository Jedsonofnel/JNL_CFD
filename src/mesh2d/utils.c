#include <math.h>
#include <string.h>

#include "mesh2d.h"
#include "internal.h"

//
// Lifecycle util
//

void jnl_mesh_free(struct jnl_mesh *mesh)
{
	if (!mesh)
		return;

	jnl_arena *arena = mesh->arena;
	arena_destroy(arena);
}

//
// Internal ones
//

enum jnl_mesh_err jnl_mesh2d_topo_sort_faces(struct jnl_mesh_topo *topo,
                                             struct jnl_patches *patches,
                                             jnl_arena *arena)
{
	i32 n = topo->n_faces;

	// Build permutation
	u64 scratch_pos = arena->pos;
	i32 *perm = ARENA_PUSH_ARRAY_Z(arena, i32, n);
	i32 *tmp_fp = ARENA_PUSH_ARRAY_Z(arena, i32, n * 2);
	i32 *tmp_own = ARENA_PUSH_ARRAY_Z(arena, i32, n);
	i32 *tmp_nb = ARENA_PUSH_ARRAY_Z(arena, i32, n);

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
		tmp_fp[f * 2] = topo->face_vertex[src * 2];
		tmp_fp[f * 2 + 1] = topo->face_vertex[src * 2 + 1];
		tmp_own[f] = topo->owner[src];
		tmp_nb[f] = topo->neighbour[src];
	}
	memcpy(topo->face_vertex, tmp_fp, n * 2 * sizeof(i32));
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

enum jnl_mesh_err jnl_mesh2d_topo_sort_cells(struct jnl_mesh_topo *topo,
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
	i32 *new_index = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells);
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
	i32 *tmp_marker = ARENA_PUSH_ARRAY_Z(arena, i32, n_cells);
	for (i32 c = 0; c < n_cells; c++)
		tmp_marker[new_index[c]] = topo->cell_marker[c];
	memcpy(topo->cell_marker, tmp_marker, n_cells * sizeof(i32));

	// Update owner/neighbour to new cell indices
	for (i32 f = 0; f < n_faces; f++) {
		topo->owner[f] = new_index[topo->owner[f]];
		if (topo->neighbour[f] >= 0)
			topo->neighbour[f] = new_index[topo->neighbour[f]];
	}

	arena_pop_to(arena, scratch_pos);
	return JNL_MESH_OK;
}

struct jnl_mesh_geom jnl_mesh2d_geom_gen(jnl_arena *arena,
                                         struct jnl_mesh_topo topo)
{
	i32 n_faces = topo.n_faces;
	i32 n_cells = topo.n_cells;

	struct jnl_mesh_geom geom = {
	    .face_cx = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_cy = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_nx = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_ny = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .face_area = ARENA_PUSH_ARRAY_Z(arena, f64, n_faces),
	    .cell_cx = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells),
	    .cell_cy = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells),
	    .cell_vol = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells),
	};

	// Face centres, areas, tentative normals
	for (i32 f = 0; f < n_faces; f++) {
		i32 p0 = topo.face_vertex[f * 2];
		i32 p1 = topo.face_vertex[f * 2 + 1];
		f64 x0 = topo.vx[p0], y0 = topo.vy[p0];
		f64 x1 = topo.vx[p1], y1 = topo.vy[p1];

		geom.face_cx[f] = 0.5 * (x0 + x1);
		geom.face_cy[f] = 0.5 * (y0 + y1);

		f64 dx = x1 - x0, dy = y1 - y0;
		f64 len = sqrt(dx * dx + dy * dy);
		geom.face_area[f] = len;

		// tentative normal: left perpendicular of edge direction
		geom.face_nx[f] = -dy / len;
		geom.face_ny[f] = dx / len;
	}

	// cell geometry - shoelace for "volume"
	for (i32 c = 0; c < n_cells; c++) {
		i32 start = topo.cell_vertex_start[c];
		i32 end = topo.cell_vertex_start[c + 1];

		f64 twice_area = 0.0;
		f64 cx_sum = 0.0;
		f64 cy_sum = 0.0;

		for (i32 i = start; i < end; i++) {
			i32 ia = topo.cell_vertex_list[i];
			i32 ib = topo.cell_vertex_list[(i + 1 < end) ? (i + 1) : start];

			f64 x0 = topo.vx[ia], y0 = topo.vy[ia];
			f64 x1 = topo.vx[ib], y1 = topo.vy[ib];

			f64 cross = x0 * y1 - x1 * y0;
			twice_area += cross;
			cx_sum += (x0 + x1) * cross;
			cy_sum += (y0 + y1) * cross;
		}

		// cell_vertex_list is CCW so twice_area > 0
		geom.cell_vol[c] = 0.5 * twice_area;

		f64 inv = 1.0 / (3.0 * twice_area);
		geom.cell_cx[c] = cx_sum * inv;
		geom.cell_cy[c] = cy_sum * inv;
	}

	// Orient normals consistently owner->neighbour
	for (i32 f = 0; f < n_faces; f++) {
		i32 o = topo.owner[f];
		i32 nb = topo.neighbour[f];

		f64 ref_x, ref_y;
		if (nb >= 0) {
			ref_x = geom.cell_cx[nb] - geom.cell_cx[o];
			ref_y = geom.cell_cy[nb] - geom.cell_cy[o];
		} else {
			ref_x = geom.face_cx[f] - geom.cell_cx[o];
			ref_y = geom.face_cy[f] - geom.cell_cy[o];
		}

		if (ref_x * geom.face_nx[f] + ref_y * geom.face_ny[f] < 0.0) {
			geom.face_nx[f] = -geom.face_nx[f];
			geom.face_ny[f] = -geom.face_ny[f];
		}
	}

	return geom;
}

struct jnl_mesh_interp jnl_mesh2d_interp_gen(jnl_arena *arena,
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

			f64 w = (d_dist > 1e-14) ? do_dist / d_dist : 0.5;
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
