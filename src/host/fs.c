#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "host.h"

static int mkdir_one(const char *path)
{
	if (mkdir(path, 0700) == 0) {
		return 0;
	}

	if (errno == EEXIST && jnl_host_path_is_dir(path)) {
		return 0;
	}

	return -1;
}

int jnl_host_path_join(char *buf, size_t cap, const char *left,
                       const char *right)
{
	if (!buf || cap == 0 || !left || !right) {
		errno = EINVAL;
		return -1;
	}

	size_t left_len = strlen(left);

	while (left_len > 1 && left[left_len - 1] == '/') {
		left_len--;
	}

	while (*right == '/') {
		right++;
	}

	int written;

	if (left_len == 0) {
		written = snprintf(buf, cap, "%s", right);
	} else if (*right == '\0') {
		written = snprintf(buf, cap, "%.*s", (int)left_len, left);
	} else if (left_len == 1 && left[0] == '/') {
		written = snprintf(buf, cap, "/%s", right);
	} else {
		written = snprintf(buf, cap, "%.*s/%s", (int)left_len, left, right);
	}

	if (written < 0 || (size_t)written >= cap) {
		errno = ENAMETOOLONG;
		return -1;
	}

	return 0;
}

int jnl_host_path_exists(const char *path)
{
	struct stat info;

	if (!path) {
		return 0;
	}

	return stat(path, &info) == 0;
}

int jnl_host_path_is_file(const char *path)
{
	struct stat info;

	if (!path || stat(path, &info) != 0) {
		return 0;
	}

	return S_ISREG(info.st_mode);
}

int jnl_host_path_is_dir(const char *path)
{
	struct stat info;

	if (!path || stat(path, &info) != 0) {
		return 0;
	}

	return S_ISDIR(info.st_mode);
}

int jnl_host_mkdir_p(const char *path)
{
	if (!path || *path == '\0') {
		errno = EINVAL;
		return -1;
	}

	size_t len = strlen(path);

	if (len >= JNL_HOST_PATH_CAP) {
		errno = ENAMETOOLONG;
		return -1;
	}

	char copy[JNL_HOST_PATH_CAP];

	memcpy(copy, path, len + 1);

	while (len > 1 && copy[len - 1] == '/') {
		copy[--len] = '\0';
	}

	for (char *cursor = copy + 1; *cursor; cursor++) {
		if (*cursor != '/') {
			continue;
		}

		*cursor = '\0';

		if (mkdir_one(copy) != 0) {
			return -1;
		}

		*cursor = '/';
	}

	return mkdir_one(copy);
}
