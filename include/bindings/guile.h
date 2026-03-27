#ifndef JNL_BNDGS_GUILE_H
#define JNL_BNDGS_GUILE_H

#include <libguile.h>

//
// Initialisation
//

void guile_boot(int argc, char **argv);

void geo2d_guile_init(void);

//
// Utility
//

SCM eval_embedded_scheme(const unsigned char *elf_data, unsigned int elf_len);

#endif
