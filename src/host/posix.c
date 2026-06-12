#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "host.h"

static int copy_path(char *buf, size_t cap, const char *path)
{
	if (!buf || cap == 0 || !path || *path == '\0') {
		errno = EINVAL;
		return -1;
	}

	int written = snprintf(buf, cap, "%s", path);

	if (written < 0 || (size_t)written >= cap) {
		errno = ENAMETOOLONG;
		return -1;
	}

	return 0;
}

static const char *absolute_env(const char *name)
{
	const char *value = getenv(name);

	if (!value || value[0] != '/') {
		return NULL;
	}

	return value;
}

static const char *home_dir(void)
{
	const char *home = absolute_env("HOME");

	if (home) {
		return home;
	}

	struct passwd *entry = getpwuid(getuid());

	if (!entry || !entry->pw_dir || entry->pw_dir[0] != '/') {
		return NULL;
	}

	return entry->pw_dir;
}

static const char *temp_dir(void)
{
	const char *tmp = absolute_env("TMPDIR");

	return tmp ? tmp : "/tmp";
}

static int home_relative(char *buf, size_t cap, const char *relative)
{
	const char *home = home_dir();

	if (!home) {
		errno = ENOENT;
		return -1;
	}

	return jnl_host_path_join(buf, cap, home, relative);
}

int jnl_host_base_dir(enum jnl_host_dir_kind kind, char *buf, size_t cap)
{
	const char *value;

	switch (kind) {
	case JNL_HOST_DIR_CONFIG:
		value = absolute_env("XDG_CONFIG_HOME");

		if (value) {
			return copy_path(buf, cap, value);
		}

		return home_relative(buf, cap, ".config");

	case JNL_HOST_DIR_DATA:
		value = absolute_env("XDG_DATA_HOME");

		if (value) {
			return copy_path(buf, cap, value);
		}

		return home_relative(buf, cap, ".local/share");

	case JNL_HOST_DIR_STATE:
		value = absolute_env("XDG_STATE_HOME");

		if (value) {
			return copy_path(buf, cap, value);
		}

		return home_relative(buf, cap, ".local/state");

	case JNL_HOST_DIR_CACHE:
		value = absolute_env("XDG_CACHE_HOME");

		if (value) {
			return copy_path(buf, cap, value);
		}

		return home_relative(buf, cap, ".cache");

	case JNL_HOST_DIR_RUNTIME:
		value = absolute_env("XDG_RUNTIME_DIR");

		if (value) {
			return copy_path(buf, cap, value);
		}

		return copy_path(buf, cap, temp_dir());

	case JNL_HOST_DIR_TEMP:
		return copy_path(buf, cap, temp_dir());

	default:
		errno = EINVAL;
		return -1;
	}
}
