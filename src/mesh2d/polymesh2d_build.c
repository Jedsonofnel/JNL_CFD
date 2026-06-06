#include <stdlib.h>
#include <string.h>

#include "polymesh2d_internal.h"
#include "jnl/common.h"

//
// Local helpers
//

static void *xcalloc(size_t n, size_t size)
{
	if (n == 0 || size == 0)
		return NULL;

	return calloc(n, size);
}

static void *xmalloc(size_t size)
{
	if (size == 0)
		return NULL;

	return malloc(size);
}

static void copy_name(char dst[JNL_PMSH2D_NAME_CAP], const char *src)
{
	if (!dst)
		return;

	if (!src) {
		dst[0] = '\0';
		return;
	}

	strncpy(dst, src, JNL_PMSH2D_NAME_CAP - 1);
	dst[JNL_PMSH2D_NAME_CAP - 1] = '\0';
}

static int cmp_marker_entry_by_marker(const void *a, const void *b)
{
	const struct jnl_pmsh2d_marker_entry *ea = a;
	const struct jnl_pmsh2d_marker_entry *eb = b;

	if (ea->marker < eb->marker)
		return -1;
	if (ea->marker > eb->marker)
		return 1;
	return 0;
}

static int cmp_cell_perm_by_region_then_old_cell(const void *a, const void *b)
{
	const struct jnl_pmsh2d_cell_perm *pa = a;
	const struct jnl_pmsh2d_cell_perm *pb = b;

	if (pa->region_id < pb->region_id)
		return -1;
	if (pa->region_id > pb->region_id)
		return 1;

	if (pa->old_cell < pb->old_cell)
		return -1;
	if (pa->old_cell > pb->old_cell)
		return 1;

	return 0;
}

static int cmp_cell_edge_by_key(const void *a, const void *b)
{
	const struct jnl_pmsh2d_cell_edge *ea = a;
	const struct jnl_pmsh2d_cell_edge *eb = b;

	if (ea->key_v0 < eb->key_v0)
		return -1;
	if (ea->key_v0 > eb->key_v0)
		return 1;

	if (ea->key_v1 < eb->key_v1)
		return -1;
	if (ea->key_v1 > eb->key_v1)
		return 1;

	if (ea->cell < eb->cell)
		return -1;
	if (ea->cell > eb->cell)
		return 1;

	return 0;
}

static i32 find_edge_by_key(const struct jnl_pmsh2d_edge *edges, i32 n_edges,
                            i32 key_v0, i32 key_v1)
{
	i32 lo = 0;
	i32 hi = n_edges;

	while (lo < hi) {
		i32 mid = lo + (hi - lo) / 2;
		const struct jnl_pmsh2d_edge *e = &edges[mid];

		if (e->key_v0 < key_v0 || (e->key_v0 == key_v0 && e->key_v1 < key_v1)) {
			lo = mid + 1;
			continue;
		}

		hi = mid;
	}

	if (lo >= n_edges)
		return JNL_PMSH2D_INVALID_ID;

	if (edges[lo].key_v0 != key_v0 || edges[lo].key_v1 != key_v1)
		return JNL_PMSH2D_INVALID_ID;

	return lo;
}

static enum jnl_mesh_err
alloc_marker_map(struct jnl_pmsh2d_marker_map *map,
                 const struct jnl_pmsh2d_desc_name *names, i32 n)
{
	if (!map)
		return JNL_MESH_ERR_INVALID_INPUT;

	memset(map, 0, sizeof(*map));

	if (n == 0)
		return JNL_MESH_OK;

	map->data = xcalloc((size_t)n, sizeof(*map->data));
	if (!map->data)
		return JNL_MESH_ERR_ALLOC;

	map->n = n;

	for (i32 i = 0; i < n; i++) {
		map->data[i].marker = names[i].marker;
		map->data[i].id = i;
		copy_name(map->data[i].name, names[i].name);
	}

	qsort(map->data, (size_t)n, sizeof(*map->data), cmp_marker_entry_by_marker);

	return JNL_MESH_OK;
}

static const struct jnl_pmsh2d_marker_entry *
marker_map_entry_by_id(const struct jnl_pmsh2d_marker_map *map, i32 id)
{
	if (!map || id < 0 || id >= map->n)
		return NULL;

	for (i32 i = 0; i < map->n; i++) {
		if (map->data[i].id == id)
			return &map->data[i];
	}

	return NULL;
}

static enum jnl_mesh_err region_id_for_marker(const struct jnl_pmsh2d_build *b,
                                              i32 marker, i32 *out_id)
{
	i32 id = jnl_pmsh2d_marker_map_find(&b->regions, marker);
	if (id < 0)
		return JNL_MESH_ERR_UNKNOWN_REGION;

	*out_id = id;
	return JNL_MESH_OK;
}

static i32 cell_nverts_desc(const struct jnl_polymesh2d_desc *desc, i32 c)
{
	return desc->cell_vertex_start[c + 1] - desc->cell_vertex_start[c];
}

static enum jnl_mesh_err
copy_cell_vertices_ccw(const struct jnl_polymesh2d_desc *desc, i32 old_cell,
                       i32 *dst)
{
	i32 start = desc->cell_vertex_start[old_cell];
	i32 end = desc->cell_vertex_start[old_cell + 1];
	i32 n = end - start;

	f64 area = jnl_pmsh2d_polygon_signed_area(
	    desc->vx, desc->vy, desc->cell_vertex_list + start, n);

	if (fabs(area) <= JNL_PMSH2D_DEFAULT_TOL)
		return JNL_MESH_ERR_DEGENERATE_CELL;

	if (area > 0.0) {
		for (i32 i = 0; i < n; i++)
			dst[i] = desc->cell_vertex_list[start + i];
		return JNL_MESH_OK;
	}

	for (i32 i = 0; i < n; i++)
		dst[i] = desc->cell_vertex_list[end - 1 - i];

	return JNL_MESH_OK;
}

static enum jnl_mesh_err emit_face_common(struct jnl_pmsh2d_build *b, i32 f,
                                          i32 v0, i32 v1, i32 owner,
                                          i32 neighbour,
                                          enum jnl_pmsh2d_face_kind kind)
{
	struct jnl_pmsh2d_topo *t = &b->mesh->topo;

	if (f < 0 || f >= t->n_faces)
		return JNL_MESH_ERR_INTERNAL;

	if (v0 < 0 || v0 >= t->n_vertices || v1 < 0 || v1 >= t->n_vertices)
		return JNL_MESH_ERR_INTERNAL;

	if (owner < 0 || owner >= t->n_cells)
		return JNL_MESH_ERR_INTERNAL;

	if (neighbour < 0 || neighbour >= t->n_cells)
		return JNL_MESH_ERR_INTERNAL;

	t->face_vertex[2 * f] = v0;
	t->face_vertex[2 * f + 1] = v1;
	t->owner[f] = owner;
	t->neighbour[f] = neighbour;
	t->face_kind[f] = (u8)kind;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err emit_internal_face(struct jnl_pmsh2d_build *b,
                                            const struct jnl_pmsh2d_edge *e)
{
	if (e->n_sides != 2)
		return JNL_MESH_ERR_INTERNAL;

	i32 f = b->next_internal_face++;
	const struct jnl_pmsh2d_cell_edge *ce0 = &b->cell_edges[e->side0];
	const struct jnl_pmsh2d_cell_edge *ce1 = &b->cell_edges[e->side1];

	return emit_face_common(b, f, ce0->v0, ce0->v1, ce0->cell, ce1->cell,
	                        JNL_PMSH2D_FACE_INTERNAL);
}

static enum jnl_mesh_err emit_boundary_face(struct jnl_pmsh2d_build *b,
                                            const struct jnl_pmsh2d_edge *e)
{
	enum jnl_mesh_err err;

	if (e->n_sides != 1)
		return JNL_MESH_ERR_INTERNAL;

	i32 f = b->next_boundary_face++;
	i32 g = b->next_ghost_cell++;
	const struct jnl_pmsh2d_cell_edge *ce = &b->cell_edges[e->side0];

	err = emit_face_common(b, f, ce->v0, ce->v1, ce->cell, g,
	                       JNL_PMSH2D_FACE_BOUNDARY);
	if (err != JNL_MESH_OK)
		return err;

	b->mesh->topo.face_patch[f] = e->patch_id;

	b->mesh->topo.cell_kind[g] = JNL_PMSH2D_CELL_GHOST;
	b->mesh->topo.cell_marker[g] = JNL_PMSH2D_INVALID_ID;
	b->mesh->topo.cell_region[g] = JNL_PMSH2D_INVALID_ID;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err emit_baffle_pair(struct jnl_pmsh2d_build *b,
                                          const struct jnl_pmsh2d_edge *e)
{
	enum jnl_mesh_err err;

	if (e->n_sides != 2)
		return JNL_MESH_ERR_INTERNAL;

	i32 f0 = b->next_baffle_face++;
	i32 g0 = b->next_ghost_cell++;
	i32 f1 = b->next_baffle_face++;
	i32 g1 = b->next_ghost_cell++;

	const struct jnl_pmsh2d_cell_edge *ce0 = &b->cell_edges[e->side0];
	const struct jnl_pmsh2d_cell_edge *ce1 = &b->cell_edges[e->side1];

	err = emit_face_common(b, f0, ce0->v0, ce0->v1, ce0->cell, g0,
	                       JNL_PMSH2D_FACE_BAFFLE);
	if (err != JNL_MESH_OK)
		return err;

	err = emit_face_common(b, f1, ce1->v0, ce1->v1, ce1->cell, g1,
	                       JNL_PMSH2D_FACE_BAFFLE);
	if (err != JNL_MESH_OK)
		return err;

	b->mesh->topo.face_baffle[f0] = e->baffle_id;
	b->mesh->topo.face_baffle[f1] = e->baffle_id;

	b->mesh->topo.paired_face[f0] = f1;
	b->mesh->topo.paired_face[f1] = f0;

	b->mesh->topo.cell_kind[g0] = JNL_PMSH2D_CELL_GHOST;
	b->mesh->topo.cell_kind[g1] = JNL_PMSH2D_CELL_GHOST;

	b->mesh->topo.cell_marker[g0] = JNL_PMSH2D_INVALID_ID;
	b->mesh->topo.cell_marker[g1] = JNL_PMSH2D_INVALID_ID;

	b->mesh->topo.cell_region[g0] = JNL_PMSH2D_INVALID_ID;
	b->mesh->topo.cell_region[g1] = JNL_PMSH2D_INVALID_ID;

	struct jnl_pmsh2d_baffle *bf = &b->mesh->baffles.data[e->baffle_id];
	i32 pair_i = b->baffle_pair_cursor[e->baffle_id]++;

	if (pair_i < 0 || pair_i >= bf->n_pairs)
		return JNL_MESH_ERR_INTERNAL;

	bf->face0[pair_i] = f0;
	bf->face1[pair_i] = f1;

	return JNL_MESH_OK;
}

//
// Marker maps
//

enum jnl_mesh_err jnl_pmsh2d_build_marker_maps(struct jnl_pmsh2d_build *b)
{
	enum jnl_mesh_err err;

	err = alloc_marker_map(&b->patches, b->desc->patch_names,
	                       b->desc->n_patch_names);
	if (err != JNL_MESH_OK)
		return err;

	err = alloc_marker_map(&b->baffles, b->desc->baffle_names,
	                       b->desc->n_baffle_names);
	if (err != JNL_MESH_OK)
		return err;

	err = alloc_marker_map(&b->regions, b->desc->region_names,
	                       b->desc->n_region_names);
	if (err != JNL_MESH_OK)
		return err;

	return JNL_MESH_OK;
}

i32 jnl_pmsh2d_marker_map_find(const struct jnl_pmsh2d_marker_map *map,
                               i32 marker)
{
	if (!map || map->n <= 0 || !map->data)
		return JNL_PMSH2D_INVALID_ID;

	i32 lo = 0;
	i32 hi = map->n;

	while (lo < hi) {
		i32 mid = lo + (hi - lo) / 2;

		if (map->data[mid].marker < marker) {
			lo = mid + 1;
			continue;
		}

		hi = mid;
	}

	if (lo >= map->n || map->data[lo].marker != marker)
		return JNL_PMSH2D_INVALID_ID;

	return map->data[lo].id;
}

//
// Canonical cells
//

enum jnl_mesh_err jnl_pmsh2d_build_canonical_cells(struct jnl_pmsh2d_build *b)
{
	enum jnl_mesh_err err;
	const struct jnl_polymesh2d_desc *desc = b->desc;

	b->n_real_cells = desc->n_cells;

	b->cell_perm = xcalloc((size_t)b->n_real_cells, sizeof(*b->cell_perm));
	b->old_to_new_cell =
	    xcalloc((size_t)b->n_real_cells, sizeof(*b->old_to_new_cell));
	b->new_to_old_cell =
	    xcalloc((size_t)b->n_real_cells, sizeof(*b->new_to_old_cell));

	if (!b->cell_perm || !b->old_to_new_cell || !b->new_to_old_cell)
		return JNL_MESH_ERR_ALLOC;

	for (i32 c = 0; c < b->n_real_cells; c++) {
		i32 region_id = JNL_PMSH2D_INVALID_ID;

		err = region_id_for_marker(b, desc->cell_marker[c], &region_id);
		if (err != JNL_MESH_OK)
			return err;

		b->cell_perm[c].old_cell = c;
		b->cell_perm[c].new_cell = c;
		b->cell_perm[c].region_id = region_id;
		b->cell_perm[c].marker = desc->cell_marker[c];
	}

	qsort(b->cell_perm, (size_t)b->n_real_cells, sizeof(*b->cell_perm),
	      cmp_cell_perm_by_region_then_old_cell);

	for (i32 new_c = 0; new_c < b->n_real_cells; new_c++) {
		i32 old_c = b->cell_perm[new_c].old_cell;

		b->cell_perm[new_c].new_cell = new_c;
		b->old_to_new_cell[old_c] = new_c;
		b->new_to_old_cell[new_c] = old_c;
	}

	b->n_cell_vertex_entries = 0;
	for (i32 new_c = 0; new_c < b->n_real_cells; new_c++) {
		i32 old_c = b->new_to_old_cell[new_c];
		b->n_cell_vertex_entries += cell_nverts_desc(desc, old_c);
	}

	b->canon_cell_vertex_start = xcalloc((size_t)b->n_real_cells + 1,
	                                     sizeof(*b->canon_cell_vertex_start));
	b->canon_cell_vertex_list = xmalloc(sizeof(*b->canon_cell_vertex_list) *
	                                    (size_t)b->n_cell_vertex_entries);
	b->canon_cell_marker =
	    xcalloc((size_t)b->n_real_cells, sizeof(*b->canon_cell_marker));
	b->canon_cell_region =
	    xcalloc((size_t)b->n_real_cells, sizeof(*b->canon_cell_region));

	if (!b->canon_cell_vertex_start || !b->canon_cell_vertex_list ||
	    !b->canon_cell_marker || !b->canon_cell_region)
		return JNL_MESH_ERR_ALLOC;

	i32 cursor = 0;
	b->canon_cell_vertex_start[0] = 0;

	for (i32 new_c = 0; new_c < b->n_real_cells; new_c++) {
		i32 old_c = b->new_to_old_cell[new_c];
		i32 nverts = cell_nverts_desc(desc, old_c);

		err = copy_cell_vertices_ccw(desc, old_c,
		                             b->canon_cell_vertex_list + cursor);
		if (err != JNL_MESH_OK)
			return err;

		b->canon_cell_marker[new_c] = desc->cell_marker[old_c];
		b->canon_cell_region[new_c] =
		    jnl_pmsh2d_marker_map_find(&b->regions, desc->cell_marker[old_c]);

		cursor += nverts;
		b->canon_cell_vertex_start[new_c + 1] = cursor;
	}

	return JNL_MESH_OK;
}

//
// Edge lowering
//

enum jnl_mesh_err jnl_pmsh2d_build_cell_edges(struct jnl_pmsh2d_build *b)
{
	b->n_cell_edges = b->n_cell_vertex_entries;

	if (b->n_cell_edges <= 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	b->cell_edges = xcalloc((size_t)b->n_cell_edges, sizeof(*b->cell_edges));
	if (!b->cell_edges)
		return JNL_MESH_ERR_ALLOC;

	i32 cursor = 0;

	for (i32 c = 0; c < b->n_real_cells; c++) {
		i32 start = b->canon_cell_vertex_start[c];
		i32 end = b->canon_cell_vertex_start[c + 1];

		for (i32 i = start; i < end; i++) {
			i32 j = (i + 1 < end) ? i + 1 : start;
			i32 v0 = b->canon_cell_vertex_list[i];
			i32 v1 = b->canon_cell_vertex_list[j];

			if (v0 == v1)
				return JNL_MESH_ERR_DEGENERATE_FACE;

			struct jnl_pmsh2d_cell_edge *ce = &b->cell_edges[cursor];

			ce->v0 = v0;
			ce->v1 = v1;
			ce->key_v0 = jnl_pmsh2d_min_i32(v0, v1);
			ce->key_v1 = jnl_pmsh2d_max_i32(v0, v1);
			ce->cell = c;
			ce->local_edge = i - start;

			cursor++;
		}
	}

	qsort(b->cell_edges, (size_t)b->n_cell_edges, sizeof(*b->cell_edges),
	      cmp_cell_edge_by_key);

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_pmsh2d_build_unique_edges(struct jnl_pmsh2d_build *b)
{
	i32 n_unique = 0;

	for (i32 i = 0; i < b->n_cell_edges;) {
		i32 j = i + 1;

		while (j < b->n_cell_edges &&
		       b->cell_edges[j].key_v0 == b->cell_edges[i].key_v0 &&
		       b->cell_edges[j].key_v1 == b->cell_edges[i].key_v1) {
			j++;
		}

		if (j - i > 2)
			return JNL_MESH_ERR_NONMANIFOLD_EDGE;

		n_unique++;
		i = j;
	}

	b->edges = xcalloc((size_t)n_unique, sizeof(*b->edges));
	if (!b->edges)
		return JNL_MESH_ERR_ALLOC;

	b->n_edges = n_unique;

	i32 out = 0;
	for (i32 i = 0; i < b->n_cell_edges;) {
		i32 j = i + 1;

		while (j < b->n_cell_edges &&
		       b->cell_edges[j].key_v0 == b->cell_edges[i].key_v0 &&
		       b->cell_edges[j].key_v1 == b->cell_edges[i].key_v1) {
			j++;
		}

		struct jnl_pmsh2d_edge *e = &b->edges[out];

		e->key_v0 = b->cell_edges[i].key_v0;
		e->key_v1 = b->cell_edges[i].key_v1;
		e->n_sides = j - i;
		e->side0 = i;
		e->side1 = (j - i == 2) ? i + 1 : JNL_PMSH2D_INVALID_ID;
		e->has_desc_edge = false;
		e->desc_kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY;
		e->marker = JNL_PMSH2D_INVALID_ID;
		e->cls = JNL_PMSH2D_EDGE_CLASS_INVALID;
		e->patch_id = JNL_PMSH2D_INVALID_ID;
		e->baffle_id = JNL_PMSH2D_INVALID_ID;

		out++;
		i = j;
	}

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_pmsh2d_attach_desc_edges(struct jnl_pmsh2d_build *b)
{
	const struct jnl_polymesh2d_desc *desc = b->desc;

	for (i32 i = 0; i < desc->n_edges; i++) {
		const struct jnl_pmsh2d_desc_edge *de = &desc->edges[i];

		i32 key_v0 = jnl_pmsh2d_min_i32(de->v0, de->v1);
		i32 key_v1 = jnl_pmsh2d_max_i32(de->v0, de->v1);
		i32 edge_id = find_edge_by_key(b->edges, b->n_edges, key_v0, key_v1);

		if (edge_id < 0)
			return JNL_MESH_ERR_EDGE_NOT_FOUND;

		struct jnl_pmsh2d_edge *e = &b->edges[edge_id];

		if (e->has_desc_edge)
			return JNL_MESH_ERR_DUPLICATE_EDGE_LABEL;

		e->has_desc_edge = true;
		e->desc_kind = de->kind;
		e->marker = de->marker;
	}

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_pmsh2d_classify_edges(struct jnl_pmsh2d_build *b)
{
	for (i32 i = 0; i < b->n_edges; i++) {
		struct jnl_pmsh2d_edge *e = &b->edges[i];

		if (e->n_sides == 1) {
			if (!e->has_desc_edge)
				return JNL_MESH_ERR_UNLABELLED_BOUNDARY;

			if (e->desc_kind != JNL_PMSH2D_DESC_EDGE_BOUNDARY)
				return JNL_MESH_ERR_INVALID_BAFFLE_EDGE;

			i32 patch_id = jnl_pmsh2d_marker_map_find(&b->patches, e->marker);
			if (patch_id < 0)
				return JNL_MESH_ERR_UNKNOWN_PATCH;

			e->cls = JNL_PMSH2D_EDGE_CLASS_BOUNDARY;
			e->patch_id = patch_id;
			continue;
		}

		if (e->n_sides != 2)
			return JNL_MESH_ERR_NONMANIFOLD_EDGE;

		if (!e->has_desc_edge) {
			e->cls = JNL_PMSH2D_EDGE_CLASS_INTERNAL;
			continue;
		}

		if (e->desc_kind == JNL_PMSH2D_DESC_EDGE_BOUNDARY)
			return JNL_MESH_ERR_INVALID_BOUNDARY_EDGE;

		if (e->desc_kind != JNL_PMSH2D_DESC_EDGE_BAFFLE)
			return JNL_MESH_ERR_INVALID_INPUT;

		i32 baffle_id = jnl_pmsh2d_marker_map_find(&b->baffles, e->marker);
		if (baffle_id < 0)
			return JNL_MESH_ERR_UNKNOWN_BAFFLE;

		e->cls = JNL_PMSH2D_EDGE_CLASS_BAFFLE;
		e->baffle_id = baffle_id;
	}

	return JNL_MESH_OK;
}

//
// Counting/allocation
//

enum jnl_mesh_err jnl_pmsh2d_count_output(struct jnl_pmsh2d_build *b)
{
	b->n_internal_faces = 0;
	b->n_boundary_faces = 0;
	b->n_baffle_faces = 0;
	b->n_ghost_cells = 0;
	b->n_baffle_pairs = 0;

	for (i32 i = 0; i < b->n_edges; i++) {
		const struct jnl_pmsh2d_edge *e = &b->edges[i];

		switch (e->cls) {
		case JNL_PMSH2D_EDGE_CLASS_INTERNAL:
			b->n_internal_faces++;
			break;

		case JNL_PMSH2D_EDGE_CLASS_BOUNDARY:
			b->n_boundary_faces++;
			b->n_ghost_cells++;
			break;

		case JNL_PMSH2D_EDGE_CLASS_BAFFLE:
			b->n_baffle_faces += 2;
			b->n_ghost_cells += 2;
			b->n_baffle_pairs++;
			break;

		default:
			return JNL_MESH_ERR_INTERNAL;
		}
	}

	b->n_faces = b->n_internal_faces + b->n_boundary_faces + b->n_baffle_faces;
	b->n_cells = b->n_real_cells + b->n_ghost_cells;
	b->n_cell_face_entries = 2 * b->n_faces;

	return JNL_MESH_OK;
}

u64 jnl_pmsh2d_arena_size(const struct jnl_pmsh2d_build *b)
{
	u64 size = 0;

	i32 nv = b->desc->n_vertices;
	i32 nc = b->n_cells;
	i32 nf = b->n_faces;
	i32 ncv = b->n_cell_vertex_entries;
	i32 ncf = b->n_cell_face_entries;

	size += ARENA_SIZE(struct jnl_polymesh2d, 1);

	size += ARENA_SIZE(f64, nv); // vx
	size += ARENA_SIZE(f64, nv); // vy

	size += ARENA_SIZE(u8, nc);  // cell_kind
	size += ARENA_SIZE(i32, nc); // cell_region
	size += ARENA_SIZE(i32, nc); // cell_marker

	size += ARENA_SIZE(i32, nc + 1); // cell_vertex_start
	size += ARENA_SIZE(i32, ncv);    // cell_vertex_list

	size += ARENA_SIZE(i32, nc + 1); // cell_face_start
	size += ARENA_SIZE(i32, ncf);    // cell_face_list
	size += ARENA_SIZE(i8, ncf);     // cell_face_sign

	size += ARENA_SIZE(i32, 2 * nf); // face_vertex
	size += ARENA_SIZE(i32, nf);     // owner
	size += ARENA_SIZE(i32, nf);     // neighbour
	size += ARENA_SIZE(u8, nf);      // face_kind
	size += ARENA_SIZE(i32, nf);     // face_patch
	size += ARENA_SIZE(i32, nf);     // face_baffle
	size += ARENA_SIZE(i32, nf);     // paired_face

	size += ARENA_SIZE(f64, nf); // face_cx
	size += ARENA_SIZE(f64, nf); // face_cy
	size += ARENA_SIZE(f64, nf); // face_nx
	size += ARENA_SIZE(f64, nf); // face_ny
	size += ARENA_SIZE(f64, nf); // face_area

	size += ARENA_SIZE(f64, nc); // cell_cx
	size += ARENA_SIZE(f64, nc); // cell_cy
	size += ARENA_SIZE(f64, nc); // cell_vol

	size += ARENA_SIZE(f64, nf); // d_x
	size += ARENA_SIZE(f64, nf); // d_y
	size += ARENA_SIZE(f64, nf); // d_mag
	size += ARENA_SIZE(f64, nf); // normal_delta
	size += ARENA_SIZE(f64, nf); // owner_face_dist

	size += ARENA_SIZE(f64, nf); // face_lerp
	size += ARENA_SIZE(f64, nf); // delta_coeff
	size += ARENA_SIZE(f64, nf); // nonorth_x
	size += ARENA_SIZE(f64, nf); // nonorth_y
	size += ARENA_SIZE(f64, nf); // skew_x
	size += ARENA_SIZE(f64, nf); // skew_y

	size += ARENA_SIZE(struct jnl_pmsh2d_patch, b->patches.n);
	size += ARENA_SIZE(struct jnl_pmsh2d_region, b->regions.n);
	size += ARENA_SIZE(struct jnl_pmsh2d_baffle, b->baffles.n);

	size += ARENA_SIZE(i32, b->n_baffle_pairs); // face0 pooled
	size += ARENA_SIZE(i32, b->n_baffle_pairs); // face1 pooled

	size += 4096; // alignment/small-growth cushion

	return size;
}

enum jnl_mesh_err jnl_pmsh2d_alloc_mesh(struct jnl_pmsh2d_build *b)
{
	u64 size = jnl_pmsh2d_arena_size(b);
	jnl_arena *arena = arena_create(size);

	if (!arena)
		return JNL_MESH_ERR_ALLOC;

	struct jnl_polymesh2d *m =
	    ARENA_PUSH_STRUCT_Z(arena, struct jnl_polymesh2d);
	if (!m) {
		arena_destroy(arena);
		return JNL_MESH_ERR_ALLOC;
	}

	m->arena = arena;
	b->mesh = m;

	struct jnl_pmsh2d_topo *t = &m->topo;
	struct jnl_pmsh2d_geom *g = &m->geom;
	struct jnl_pmsh2d_interp *it = &m->interp;

	t->n_vertices = b->desc->n_vertices;
	t->n_real_cells = b->n_real_cells;
	t->n_ghost_cells = b->n_ghost_cells;
	t->n_cells = b->n_cells;

	t->n_internal_faces = b->n_internal_faces;
	t->n_boundary_faces = b->n_boundary_faces;
	t->n_baffle_faces = b->n_baffle_faces;
	t->n_faces = b->n_faces;

	t->vx = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_vertices);
	t->vy = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_vertices);

	t->cell_kind = ARENA_PUSH_ARRAY_Z(arena, u8, t->n_cells);
	t->cell_region = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_cells);
	t->cell_marker = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_cells);

	t->cell_vertex_start = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_cells + 1);
	t->cell_vertex_list =
	    ARENA_PUSH_ARRAY_Z(arena, i32, b->n_cell_vertex_entries);

	t->cell_face_start = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_cells + 1);
	t->cell_face_list = ARENA_PUSH_ARRAY_Z(arena, i32, b->n_cell_face_entries);
	t->cell_face_sign = ARENA_PUSH_ARRAY_Z(arena, i8, b->n_cell_face_entries);

	t->face_vertex = ARENA_PUSH_ARRAY_Z(arena, i32, 2 * t->n_faces);
	t->owner = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_faces);
	t->neighbour = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_faces);
	t->face_kind = ARENA_PUSH_ARRAY_Z(arena, u8, t->n_faces);
	t->face_patch = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_faces);
	t->face_baffle = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_faces);
	t->paired_face = ARENA_PUSH_ARRAY_Z(arena, i32, t->n_faces);

	g->face_cx = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->face_cy = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->face_nx = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->face_ny = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->face_area = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);

	g->cell_cx = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_cells);
	g->cell_cy = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_cells);
	g->cell_vol = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_cells);

	g->d_x = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->d_y = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->d_mag = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->normal_delta = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	g->owner_face_dist = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);

	it->face_lerp = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	it->delta_coeff = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	it->nonorth_x = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	it->nonorth_y = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	it->skew_x = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);
	it->skew_y = ARENA_PUSH_ARRAY_Z(arena, f64, t->n_faces);

	m->patches.n_patches = b->patches.n;
	m->patches.data =
	    ARENA_PUSH_ARRAY_Z(arena, struct jnl_pmsh2d_patch, b->patches.n);

	m->regions.n_regions = b->regions.n;
	m->regions.data =
	    ARENA_PUSH_ARRAY_Z(arena, struct jnl_pmsh2d_region, b->regions.n);

	m->baffles.n_baffles = b->baffles.n;
	m->baffles.n_baffle_faces = b->n_baffle_faces;
	m->baffles.data =
	    ARENA_PUSH_ARRAY_Z(arena, struct jnl_pmsh2d_baffle, b->baffles.n);

	jnl_pmsh2d_fill_i32(t->cell_region, t->n_cells, JNL_PMSH2D_INVALID_ID);
	jnl_pmsh2d_fill_i32(t->cell_marker, t->n_cells, JNL_PMSH2D_INVALID_ID);
	jnl_pmsh2d_fill_i32(t->face_patch, t->n_faces, JNL_PMSH2D_INVALID_ID);
	jnl_pmsh2d_fill_i32(t->face_baffle, t->n_faces, JNL_PMSH2D_INVALID_ID);
	jnl_pmsh2d_fill_i32(t->paired_face, t->n_faces, JNL_PMSH2D_INVALID_ID);

	return JNL_MESH_OK;
}

//
// Topology emission
//

enum jnl_mesh_err jnl_pmsh2d_fill_vertices_and_cells(struct jnl_pmsh2d_build *b)
{
	const struct jnl_polymesh2d_desc *desc = b->desc;
	struct jnl_pmsh2d_topo *t = &b->mesh->topo;

	memcpy(t->vx, desc->vx, sizeof(f64) * (size_t)t->n_vertices);
	memcpy(t->vy, desc->vy, sizeof(f64) * (size_t)t->n_vertices);

	for (i32 c = 0; c < b->n_real_cells; c++) {
		t->cell_kind[c] = JNL_PMSH2D_CELL_REAL;
		t->cell_marker[c] = b->canon_cell_marker[c];
		t->cell_region[c] = b->canon_cell_region[c];
		t->cell_vertex_start[c] = b->canon_cell_vertex_start[c];
	}

	t->cell_vertex_start[b->n_real_cells] =
	    b->canon_cell_vertex_start[b->n_real_cells];

	for (i32 g = b->n_real_cells; g < b->n_cells; g++) {
		t->cell_kind[g] = JNL_PMSH2D_CELL_GHOST;
		t->cell_marker[g] = JNL_PMSH2D_INVALID_ID;
		t->cell_region[g] = JNL_PMSH2D_INVALID_ID;
		t->cell_vertex_start[g + 1] = t->cell_vertex_start[g];
	}

	memcpy(t->cell_vertex_list, b->canon_cell_vertex_list,
	       sizeof(i32) * (size_t)b->n_cell_vertex_entries);

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_pmsh2d_fill_regions(struct jnl_pmsh2d_build *b)
{
	struct jnl_polymesh2d *m = b->mesh;

	for (i32 r = 0; r < b->regions.n; r++) {
		const struct jnl_pmsh2d_marker_entry *entry =
		    marker_map_entry_by_id(&b->regions, r);
		if (!entry)
			return JNL_MESH_ERR_INTERNAL;

		struct jnl_pmsh2d_region *region = &m->regions.data[r];

		copy_name(region->name, entry->name);
		region->marker = entry->marker;
		region->start_cell = 0;
		region->n_cells = 0;
	}

	i32 c = 0;
	while (c < b->n_real_cells) {
		i32 region_id = b->canon_cell_region[c];
		i32 start = c;

		while (c < b->n_real_cells && b->canon_cell_region[c] == region_id) {
			c++;
		}

		if (region_id < 0 || region_id >= m->regions.n_regions)
			return JNL_MESH_ERR_INTERNAL;

		m->regions.data[region_id].start_cell = start;
		m->regions.data[region_id].n_cells = c - start;
	}

	return JNL_MESH_OK;
}

enum jnl_mesh_err
jnl_pmsh2d_fill_patches_and_baffles(struct jnl_pmsh2d_build *b)
{
	struct jnl_polymesh2d *m = b->mesh;

	for (i32 p = 0; p < b->patches.n; p++) {
		const struct jnl_pmsh2d_marker_entry *entry =
		    marker_map_entry_by_id(&b->patches, p);
		if (!entry)
			return JNL_MESH_ERR_INTERNAL;

		struct jnl_pmsh2d_patch *patch = &m->patches.data[p];

		copy_name(patch->name, entry->name);
		patch->marker = entry->marker;
		patch->start_face = 0;
		patch->n_faces = 0;
	}

	for (i32 k = 0; k < b->baffles.n; k++) {
		const struct jnl_pmsh2d_marker_entry *entry =
		    marker_map_entry_by_id(&b->baffles, k);
		if (!entry)
			return JNL_MESH_ERR_INTERNAL;

		struct jnl_pmsh2d_baffle *bf = &m->baffles.data[k];

		copy_name(bf->name, entry->name);
		bf->marker = entry->marker;
		bf->start_face = 0;
		bf->n_faces = 0;
		bf->n_pairs = 0;
		bf->face0 = NULL;
		bf->face1 = NULL;
	}

	for (i32 i = 0; i < b->n_edges; i++) {
		const struct jnl_pmsh2d_edge *e = &b->edges[i];

		if (e->cls == JNL_PMSH2D_EDGE_CLASS_BOUNDARY)
			m->patches.data[e->patch_id].n_faces++;

		if (e->cls == JNL_PMSH2D_EDGE_CLASS_BAFFLE) {
			m->baffles.data[e->baffle_id].n_faces += 2;
			m->baffles.data[e->baffle_id].n_pairs++;
		}
	}

	i32 cursor = m->topo.n_internal_faces;
	for (i32 p = 0; p < m->patches.n_patches; p++) {
		m->patches.data[p].start_face = cursor;
		cursor += m->patches.data[p].n_faces;
		m->patches.data[p].n_faces = 0;
	}

	cursor = m->topo.n_internal_faces + m->topo.n_boundary_faces;
	for (i32 k = 0; k < m->baffles.n_baffles; k++) {
		struct jnl_pmsh2d_baffle *bf = &m->baffles.data[k];

		i32 n_pairs = bf->n_pairs;

		bf->start_face = cursor;
		cursor += bf->n_faces;

		if (n_pairs > 0) {
			bf->face0 = ARENA_PUSH_ARRAY_Z(m->arena, i32, n_pairs);
			bf->face1 = ARENA_PUSH_ARRAY_Z(m->arena, i32, n_pairs);
			if (!bf->face0 || !bf->face1)
				return JNL_MESH_ERR_ALLOC;
		}

		bf->n_faces = 0;
		bf->n_pairs = n_pairs;
	}

	b->baffle_pair_cursor =
	    xcalloc((size_t)m->baffles.n_baffles, sizeof(*b->baffle_pair_cursor));
	if (m->baffles.n_baffles > 0 && !b->baffle_pair_cursor)
		return JNL_MESH_ERR_ALLOC;

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_pmsh2d_fill_faces(struct jnl_pmsh2d_build *b)
{
	enum jnl_mesh_err err;
	struct jnl_polymesh2d *m = b->mesh;

	b->next_internal_face = 0;
	b->next_boundary_face = m->topo.n_internal_faces;
	b->next_baffle_face = m->topo.n_internal_faces + m->topo.n_boundary_faces;
	b->next_ghost_cell = m->topo.n_real_cells;

	for (i32 i = 0; i < b->n_edges; i++) {
		const struct jnl_pmsh2d_edge *e = &b->edges[i];

		if (e->cls != JNL_PMSH2D_EDGE_CLASS_INTERNAL)
			continue;

		err = emit_internal_face(b, e);
		if (err != JNL_MESH_OK)
			return err;
	}

	for (i32 p = 0; p < m->patches.n_patches; p++) {
		struct jnl_pmsh2d_patch *patch = &m->patches.data[p];

		patch->start_face = b->next_boundary_face;

		for (i32 i = 0; i < b->n_edges; i++) {
			const struct jnl_pmsh2d_edge *e = &b->edges[i];

			if (e->cls != JNL_PMSH2D_EDGE_CLASS_BOUNDARY)
				continue;

			if (e->patch_id != p)
				continue;

			err = emit_boundary_face(b, e);
			if (err != JNL_MESH_OK)
				return err;

			patch->n_faces++;
		}
	}

	for (i32 k = 0; k < m->baffles.n_baffles; k++) {
		struct jnl_pmsh2d_baffle *bf = &m->baffles.data[k];

		bf->start_face = b->next_baffle_face;
		bf->n_faces = 0;

		for (i32 i = 0; i < b->n_edges; i++) {
			const struct jnl_pmsh2d_edge *e = &b->edges[i];

			if (e->cls != JNL_PMSH2D_EDGE_CLASS_BAFFLE)
				continue;

			if (e->baffle_id != k)
				continue;

			err = emit_baffle_pair(b, e);
			if (err != JNL_MESH_OK)
				return err;

			bf->n_faces += 2;
		}
	}

	if (b->next_internal_face != m->topo.n_internal_faces)
		return JNL_MESH_ERR_INTERNAL;

	if (b->next_boundary_face !=
	    m->topo.n_internal_faces + m->topo.n_boundary_faces)
		return JNL_MESH_ERR_INTERNAL;

	if (b->next_baffle_face != m->topo.n_faces)
		return JNL_MESH_ERR_INTERNAL;

	if (b->next_ghost_cell != m->topo.n_cells)
		return JNL_MESH_ERR_INTERNAL;

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_pmsh2d_build_cell_face_csr(struct jnl_pmsh2d_build *b)
{
	struct jnl_pmsh2d_topo *t = &b->mesh->topo;
	i32 *counts = xcalloc((size_t)t->n_cells, sizeof(*counts));
	i32 *cursor = xcalloc((size_t)t->n_cells, sizeof(*cursor));

	if (!counts || !cursor) {
		free(counts);
		free(cursor);
		return JNL_MESH_ERR_ALLOC;
	}

	for (i32 f = 0; f < t->n_faces; f++) {
		i32 o = t->owner[f];
		i32 n = t->neighbour[f];

		if (o < 0 || o >= t->n_cells || n < 0 || n >= t->n_cells) {
			free(counts);
			free(cursor);
			return JNL_MESH_ERR_INTERNAL;
		}

		counts[o]++;
		counts[n]++;
	}

	t->cell_face_start[0] = 0;
	for (i32 c = 0; c < t->n_cells; c++)
		t->cell_face_start[c + 1] = t->cell_face_start[c] + counts[c];

	if (t->cell_face_start[t->n_cells] != b->n_cell_face_entries) {
		free(counts);
		free(cursor);
		return JNL_MESH_ERR_INTERNAL;
	}

	memcpy(cursor, t->cell_face_start, sizeof(i32) * (size_t)t->n_cells);

	for (i32 f = 0; f < t->n_faces; f++) {
		i32 o = t->owner[f];
		i32 n = t->neighbour[f];

		i32 po = cursor[o]++;
		t->cell_face_list[po] = f;
		t->cell_face_sign[po] = +1;

		i32 pn = cursor[n]++;
		t->cell_face_list[pn] = f;
		t->cell_face_sign[pn] = -1;
	}

	free(counts);
	free(cursor);

	return JNL_MESH_OK;
}
