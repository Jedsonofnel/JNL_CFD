#include <string.h>
#include <libguile.h>

#include "bindings/guile.h"
#include "bindings/jnl/cfd/repl.go.h"
#include "bindings/jnl/cfd/geo2d.go.h"

static void register_geo(void *data);

static void inner_main(void *data, int argc, char **argv)
{
	(void) data;

	scm_c_define_module("jnl cfd geo2d", register_geo, NULL);

	if (argc > 1) {
		scm_shell(argc, argv);
		return;
	}

	eval_embedded_scheme(repl_go, repl_go_len);
}

void guile_boot(int argc, char **argv)
{
	scm_boot_guile(argc, argv, inner_main, NULL);
}

//
// Module registration
//

static void register_geo(void *data)
{
	(void) data;
	geo2d_guile_init();
	eval_embedded_scheme(geo2d_go, geo2d_go_len);
}


//
// Utility
//

SCM_API SCM scm_load_thunk_from_memory(SCM bv);

SCM eval_embedded_scheme(const unsigned char *elf_data,
			 unsigned int elf_len)
{
	SCM bv = scm_c_make_bytevector(elf_len);
	memcpy(SCM_BYTEVECTOR_CONTENTS(bv), elf_data, elf_len);
	SCM thunk = scm_load_thunk_from_memory(bv);
	return scm_call_0(thunk);
}
