#ifndef JNL_TEST_H
#define JNL_TEST_H

#include <stdio.h>
#include <stdlib.h>

#define TEST_ASSERT(cond)                                                      \
	do {                                                                       \
		if (!(cond)) {                                                         \
			fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);    \
			exit(1);                                                           \
		}                                                                      \
	} while (0)

#define TEST_ASSERT_MSG(cond, ...)                                             \
	do {                                                                       \
		if (!(cond)) {                                                         \
			fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);               \
			fprintf(stderr, __VA_ARGS__);                                      \
			fprintf(stderr, "\n");                                             \
			exit(1);                                                           \
		}                                                                      \
	} while (0)

#define TEST_PASS() printf("PASS %s\n", __FILE__)

#endif
