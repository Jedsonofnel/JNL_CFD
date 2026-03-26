#include "bindings/guile.h"
#include <libguile.h>

static void register_module(void *data)
{
	(void) data;
	geo2d_guile_init();
}

static void inner_main(void *data, int argc, char **argv)
{
	(void) data;

	SCM module = scm_c_define_module("jnl cfd", register_module, NULL);
	scm_set_current_module(module);

	if (argc > 1) {
		scm_shell(argc, argv);
		return;
	}

	scm_c_eval_string("(use-modules (system repl repl)             \n"
			  "             (system repl common))           \n"
			  "                                             \n"
			  "(display \"JNL CFD 0.1\\n\")                \n"
			  "(display \"Type ,help for help.\\n\\n\")     \n"
			  "                                             \n"
			  // Override prompt — repl-default-prompt-string reads current module
			  "(repl-default-prompt-set!                   \n"
			  "  (lambda (repl)                             \n"
			  "    (format #f \"jnl-cfd> \")))              \n"
			  "                                             \n"
			  "(run-repl (make-repl 'scheme))               \n");
}

void guile_boot(int argc, char **argv)
{
	scm_boot_guile(argc, argv, inner_main, NULL);
}
