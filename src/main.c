#include <stdlib.h>
#include <unistd.h>

#include "ui.h"
#include "bindings/guile.h"

int main(int argc, char **argv)
{
	// mabye spawn here ?
	guile_boot(argc, argv);	// launches repl
	return EXIT_SUCCESS;
}
