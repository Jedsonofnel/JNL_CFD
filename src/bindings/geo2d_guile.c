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

static SCM scm_pslg_node_add(SCM obj, SCM x, SCM y, SCM marker)
{
	pslg *g = scm_to_pslg(obj);
	u32 idx = pslg_node_add(g, scm_to_double(x),
				scm_to_double(y),
				scm_to_int32(marker));
	scm_remember_upto_here_1(obj);
	return scm_from_uint32(idx);
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

	// PSLG
	name = scm_from_utf8_symbol("geo2d-pslg");
	slots = scm_list_1(scm_from_utf8_symbol("pslg"));
	finalizer = pslg_finalizer;
	guile_pslg_type =
	    scm_make_foreign_object_type(name, slots, finalizer);

	scm_c_define_gsubr("make-pslg", 0, 0, 0, (void *) scm_make_pslg);
	scm_c_define_gsubr("pslg-add-node", 4, 0, 0,
			   (void *) scm_pslg_node_add);

	return;
}
