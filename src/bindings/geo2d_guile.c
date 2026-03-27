#include <libguile.h>

#include "geo2d.h"

static SCM guile_node_array_type;
static SCM guile_pslg_type;

//
// Node integration
//

static SCM scm_make_node_array(void)
{
	node_array *ns = malloc(sizeof(node_array));
	node_array_init(ns);
	return scm_make_foreign_object_1(guile_node_array_type, ns);
}

static void node_array_finalizer(SCM obj)
{
	node_array *ns = scm_foreign_object_ref(obj, 0);
	node_array_free(ns);
	free(ns);
}

static node_array *scm_to_node_array(SCM obj)
{
	scm_assert_foreign_object_type(guile_node_array_type, obj);
	return scm_foreign_object_ref(obj, 0);
}

static SCM scm_node_array_len(SCM obj)
{
	node_array *ns = scm_to_node_array(obj);
	u32 len = ns->len;
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(len);
}

static SCM scm_node_array_add(SCM obj, SCM x, SCM y, SCM marker)
{
	node_array *ns = scm_to_node_array(obj);
	u32 idx = node_array_add(ns, scm_to_double(x),
				 scm_to_double(y),
				 scm_to_int32(marker));

	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
}

static SCM scm_node_array_find_nearest(SCM obj, SCM x, SCM y)
{
	node_array *ns = scm_to_node_array(obj);
	i32 idx = node_array_find_nearest(ns, scm_to_double(x),
					  scm_to_double(y));
	scm_remember_upto_here_1(obj);

	if (idx == GEO_NOT_FOUND) {
		scm_misc_error("node-array-find-nearest",
			       "node array is empty", SCM_EOL);
	}

	return scm_from_int32(idx);
}

static SCM scm_node_array_find_or_add(SCM obj, SCM x, SCM y, SCM marker,
				      SCM eps)
{
	node_array *ns = scm_to_node_array(obj);
	u32 idx = node_array_find_or_add(ns, scm_to_double(x),
					 scm_to_double(y),
					 scm_to_int32(marker),
					 scm_to_double(eps));

	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);

}

static SCM scm_node_array_get(SCM obj, SCM idx)
{
	node_array *ns = scm_to_node_array(obj);
	f64 nx, ny;
	i32 result = node_array_get(ns, scm_to_uint32(idx), &nx, &ny);

	scm_remember_upto_here_1(obj);

	if (result == GEO_OOB) {
		scm_out_of_range("node-array-get", idx);
	}

	return scm_list_2(scm_from_double(nx), scm_from_double(ny));
}

static SCM scm_node_array_write(SCM obj, SCM port)
{
	if (SCM_UNBNDP(port)) {
		port = scm_current_output_port();
	}

	scm_flush(port);

	int fd = scm_to_int(scm_fileno(port));
	FILE *f = fdopen(fd, "w");
	if (!f) {
		scm_syserror("node-array-write");
	}

	node_array *ns = scm_to_node_array(obj);
	node_array_write(f, ns);

	fflush(f);

	scm_remember_upto_here_1(obj);
	return SCM_UNSPECIFIED;
}

//
// PSLG integration
//

static SCM scm_make_pslg(void)
{
	pslg *g = malloc(sizeof(pslg));
	pslg_init(g);
	return scm_make_foreign_object_1(guile_pslg_type, g);
}

static void pslg_finalizer(SCM obj)
{
	pslg *g = scm_foreign_object_ref(obj, 0);
	pslg_free(g);
	free(g);
}

static pslg *scm_to_pslg(SCM obj)
{
	scm_assert_foreign_object_type(guile_pslg_type, obj);
	return scm_foreign_object_ref(obj, 0);
}

static SCM scm_pslg_nodes_len(SCM obj)
{
	pslg *g = scm_to_pslg(obj);
	return scm_from_uint32(g->nodes.len);
}

static SCM scm_pslg_edges_len(SCM obj)
{
	pslg *g = scm_to_pslg(obj);
	return scm_from_uint32(g->elen);
}

static SCM scm_pslg_holes_len(SCM obj)
{
	pslg *g = scm_to_pslg(obj);
	return scm_from_uint32(g->hlen);
}

static SCM scm_pslg_regions_len(SCM obj)
{
	pslg *g = scm_to_pslg(obj);
	return scm_from_uint32(g->rlen);
}

static SCM scm_pslg_node_add(SCM obj, SCM x, SCM y, SCM marker)
{
	pslg *g = scm_to_pslg(obj);
	u32 idx = pslg_node_add(g, scm_to_double(x),
				scm_to_double(y),
				scm_to_int32(marker));
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
}

static SCM scm_pslg_node_find_nearest(SCM obj, SCM x, SCM y)
{
	pslg *g = scm_to_pslg(obj);
	i32 idx = pslg_node_find_nearest(g, scm_to_double(x),
					 scm_to_double(y));
	scm_remember_upto_here_1(obj);

	if (idx == GEO_NOT_FOUND) {
		scm_misc_error("pslg-node-find-nearest",
			       "pslg nodes is empty", SCM_EOL);
	}

	return scm_from_int32(idx);
}

static SCM scm_pslg_node_find_or_add(SCM obj, SCM x, SCM y, SCM marker,
				     SCM eps)
{
	pslg *g = scm_to_pslg(obj);
	u32 idx = pslg_node_find_or_add(g, scm_to_double(x),
					scm_to_double(y),
					scm_to_int32(marker),
					scm_to_double(eps));
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
}

static SCM scm_pslg_node_get(SCM obj, SCM idx)
{
	pslg *g = scm_to_pslg(obj);
	f64 nx, ny;
	i32 result = pslg_node_get(g, scm_to_uint32(idx), &nx, &ny);

	scm_remember_upto_here_1(obj);

	if (result == GEO_OOB) {
		scm_out_of_range("pslg-node-get", idx);
	}

	return scm_list_2(scm_from_double(nx), scm_from_double(ny));
}

static SCM scm_pslg_edge_add(SCM obj, SCM p, SCM q, SCM marker)
{
	pslg *g = scm_to_pslg(obj);
	u32 idx = pslg_edge_add(g, scm_to_uint32(p),
				scm_to_uint32(q),
				scm_to_int32(marker));
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
}

static SCM scm_pslg_hole_add(SCM obj, SCM x, SCM y)
{
	pslg *g = scm_to_pslg(obj);
	u32 idx = pslg_hole_add(g, scm_to_double(x), scm_to_double(y));
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
}

static SCM scm_pslg_region_add(SCM obj, SCM x, SCM y, SCM marker,
			       SCM max_area)
{
	pslg *g = scm_to_pslg(obj);
	u32 idx = pslg_region_add(g, scm_to_double(x),
				  scm_to_double(y),
				  scm_to_int32(marker),
				  scm_to_double(max_area));
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
}

static SCM scm_pslg_write(SCM obj, SCM port)
{
	if (SCM_UNBNDP(port)) {
		port = scm_current_output_port();
	}

	scm_flush(port);

	int fd = scm_to_int(scm_fileno(port));
	FILE *f = fdopen(fd, "w");
	if (!f) {
		scm_syserror("node-array-write");
	}

	pslg *g = scm_to_pslg(obj);
	pslg_write(f, g);

	fflush(f);

	scm_remember_upto_here_1(obj);
	return SCM_UNSPECIFIED;
}

//
// The single exported function
//

void geo2d_guile_init(void)
{
	// Node array
	SCM name = scm_from_utf8_symbol("geo2d-node-array");
	SCM slots = scm_list_1(scm_from_utf8_symbol("nodes"));
	scm_t_struct_finalize finalizer = node_array_finalizer;
	guile_node_array_type =
	    scm_make_foreign_object_type(name, slots, finalizer);

	scm_c_define_gsubr("make-node-array", 0, 0, 0,
			   scm_make_node_array);
	scm_c_define_gsubr("node-array-len", 1, 0, 0, scm_node_array_len);
	scm_c_define_gsubr("node-array-add", 4, 0, 0, scm_node_array_add);
	scm_c_define_gsubr("node-array-find-nearest", 3, 0, 0,
			   scm_node_array_find_nearest);
	scm_c_define_gsubr("node-array-find-or-add", 5, 0, 0,
			   scm_node_array_find_or_add);
	scm_c_define_gsubr("node-array-get", 2, 0, 0, scm_node_array_get);
	scm_c_define_gsubr("node-array-write", 1, 1, 0,
			   scm_node_array_write);

	// PSLG
	name = scm_from_utf8_symbol("geo2d-pslg");
	slots = scm_list_1(scm_from_utf8_symbol("pslg"));
	finalizer = pslg_finalizer;
	guile_pslg_type =
	    scm_make_foreign_object_type(name, slots, finalizer);

	scm_c_define_gsubr("make-pslg", 0, 0, 0, scm_make_pslg);
	scm_c_define_gsubr("pslg-nodes-len", 0, 0, 0, scm_pslg_nodes_len);
	scm_c_define_gsubr("pslg-edges-len", 0, 0, 0, scm_pslg_edges_len);
	scm_c_define_gsubr("pslg-holes-len", 0, 0, 0, scm_pslg_holes_len);
	scm_c_define_gsubr("pslg-regions-len", 0, 0, 0,
			   scm_pslg_regions_len);
	scm_c_define_gsubr("pslg-node-add", 4, 0, 0, scm_pslg_node_add);
	scm_c_define_gsubr("pslg-node-find-nearest", 3, 0, 0,
			   scm_pslg_node_find_nearest);
	scm_c_define_gsubr("pslg-node-find-or-add", 5, 0, 0,
			   scm_pslg_node_find_or_add);
	scm_c_define_gsubr("pslg-node-get", 2, 0, 0, scm_pslg_node_get);
	scm_c_define_gsubr("pslg-edge-add", 4, 0, 0, scm_pslg_edge_add);
	scm_c_define_gsubr("pslg-hole-add", 3, 0, 0, scm_pslg_hole_add);
	scm_c_define_gsubr("pslg-region-add", 5, 0, 0,
			   scm_pslg_region_add);
	scm_c_define_gsubr("pslg-write", 1, 1, 0, scm_pslg_write);

	return;
}
