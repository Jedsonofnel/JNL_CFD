#ifndef JNL_HOST_H
#define JNL_HOST_H

#include <stddef.h>

#define JNL_HOST_PATH_CAP 4096

enum jnl_host_dir_kind {
	JNL_HOST_DIR_CONFIG,
	JNL_HOST_DIR_DATA,
	JNL_HOST_DIR_STATE,
	JNL_HOST_DIR_CACHE,
	JNL_HOST_DIR_RUNTIME,
	JNL_HOST_DIR_TEMP,
};

/*
 * Resolve a host-standard base directory.
 *
 * The returned path does not include the application-specific "jnl"
 * component. Returns 0 on success and -1 on failure.
 */
int jnl_host_base_dir(enum jnl_host_dir_kind kind, char *buf, size_t cap);

/*
 * Join two path components.
 *
 * Returns 0 on success and -1 if the arguments are invalid or the output
 * buffer is too small.
 */
int jnl_host_path_join(char *buf, size_t cap, const char *left,
                       const char *right);

/*
 * Create a directory and any missing parents.
 *
 * Directories are created with mode 0700, subject to the process umask.
 */
int jnl_host_mkdir_p(const char *path);

int jnl_host_path_exists(const char *path);
int jnl_host_path_is_file(const char *path);
int jnl_host_path_is_dir(const char *path);

#endif
