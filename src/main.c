#include <stdlib.h>
#include <stdio.h>

#include "geo2d.h"

int main(void)
{
	pslg *domain = &(pslg) { 0 };
	pslg_init(domain);

	for (f32 i = 0; i < 10; i++) {
		u8 index = pslg_node_add(domain, i, 1.54 * i, 0);
		printf("Adding [%.2f, %.2f] => %u\n", i, 1.54 * i, index);
	}

	pslg_node_add(domain, 1.0, 2.0, 0);

	u32 idx = pslg_node_find_nearest(domain, 1.0, 2.1);
	f64 nx, ny;
	pslg_node_get(domain, idx, &nx, &ny);

	printf("Closest node to [%.2f, %.2f] => [%.2f %.2f]\n", 1.0, 2.1,
	       nx, ny);

	node_array_write(stdout, &domain->nodes);
	pslg_write(stdout, domain);

	return EXIT_SUCCESS;
}
