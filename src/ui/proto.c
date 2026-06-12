#include <unistd.h>
#include <errno.h>

#include "proto.h"

int jnl_proto_send_all(int fd, const void *buf, size_t n)
{
	const u8 *p = buf;

	while (n > 0) {
		ssize_t w = write(fd, p, n);

		if (w < 0 && errno == EINTR)
			continue;

		if (w <= 0)
			return -1;

		p += (size_t)w;
		n -= (size_t)w;
	}

	return 0;
}

int jnl_proto_recv_all(int fd, void *buf, size_t n)
{
	u8 *p = buf;

	while (n > 0) {
		ssize_t r = read(fd, p, n);

		if (r < 0 && errno == EINTR)
			continue;

		if (r <= 0)
			return -1;

		p += (size_t)r;
		n -= (size_t)r;
	}

	return 0;
}
