#include <stdlib.h>

#include "bindings/guile.h"

int main(int argc, char **argv)
{
	guile_boot(argc, argv);
	return EXIT_SUCCESS;
}
