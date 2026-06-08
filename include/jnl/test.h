#ifndef JNL_TEST_H
#define JNL_TEST_H

#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef JNL_TEST_MSG_CAP
#define JNL_TEST_MSG_CAP 1024
#endif

#ifndef JNL_TEST_MAX_FAILURES
#define JNL_TEST_MAX_FAILURES 128
#endif

struct jnl_test_failure {
	const char *test_name;
	const char *file;
	int line;
	char msg[JNL_TEST_MSG_CAP];
};

struct jnl_test_suite {
	const char *name;

	int passed;
	int failed;
	int skipped;
	int total;

	const char *current_name;

	struct jnl_test_failure failures[JNL_TEST_MAX_FAILURES];
	int n_failures;
	int n_unstored_failures;

	jmp_buf jump;
};

typedef void (*jnl_test_fn)(void);

static struct jnl_test_suite *jnl_test_current_suite = NULL;

//
// Suite
//

static inline struct jnl_test_suite jnl_test_begin(const char *name)
{
	struct jnl_test_suite t;

	memset(&t, 0, sizeof(t));
	t.name = name ? name : "tests";

	printf("%s\n", t.name);

	return t;
}

static inline void jnl_test_record_failure(struct jnl_test_suite *t,
                                           const char *file, int line,
                                           const char *msg)
{
	if (t->n_failures < JNL_TEST_MAX_FAILURES) {
		struct jnl_test_failure *f = &t->failures[t->n_failures++];

		f->test_name = t->current_name;
		f->file = file;
		f->line = line;

		snprintf(f->msg, sizeof(f->msg), "%s", msg);
	} else {
		t->n_unstored_failures++;
	}
}

static inline void jnl_test_fail_at(const char *file, int line, const char *fmt,
                                    ...)
{
	va_list args;
	char msg[JNL_TEST_MSG_CAP];

	if (!jnl_test_current_suite) {
		fprintf(stderr, "jnl/test.h: assertion used outside jnl_test_run()\n");
		exit(2);
	}

	va_start(args, fmt);
	vsnprintf(msg, sizeof(msg), fmt, args);
	va_end(args);

	jnl_test_record_failure(jnl_test_current_suite, file, line, msg);

	longjmp(jnl_test_current_suite->jump, 1);
}

static inline void jnl_test_run(struct jnl_test_suite *t, const char *name,
                                jnl_test_fn fn)
{
	t->current_name = name;
	t->total++;

	jnl_test_current_suite = t;

	if (setjmp(t->jump) == 0) {
		fn();
		t->passed++;
		putchar('.');
	} else {
		t->failed++;
		putchar('F');
	}

	jnl_test_current_suite = NULL;
}

static inline void jnl_test_skip(struct jnl_test_suite *t, const char *name)
{
	t->total++;
	t->skipped++;
	putchar('S');

	if (t->n_failures < JNL_TEST_MAX_FAILURES) {
		struct jnl_test_failure *f = &t->failures[t->n_failures++];

		f->test_name = name;
		f->file = NULL;
		f->line = 0;
		snprintf(f->msg, sizeof(f->msg), "skipped");
	}
}

static inline void jnl_test_print_failures(struct jnl_test_suite *t)
{
	if (t->n_failures == 0)
		return;

	printf("\n\nFailures:\n");

	for (int i = 0; i < t->n_failures; i++) {
		struct jnl_test_failure *f = &t->failures[i];

		printf("\n  %d) %s\n", i + 1,
		       f->test_name ? f->test_name : "(unknown)");

		if (f->file) {
			printf("     %s:%d\n", f->file, f->line);
		}

		printf("     %s\n", f->msg);
	}

	if (t->n_unstored_failures > 0) {
		printf("\n  ... plus %d more failure(s) not stored. "
		       "Increase JNL_TEST_MAX_FAILURES.\n",
		       t->n_unstored_failures);
	}
}

static inline int jnl_test_end(struct jnl_test_suite *t)
{
	const char *machine = getenv("JNL_TEST_MACHINE");

	putchar('\n');

	jnl_test_print_failures(t);

	printf("\n%d passed  %d failed  %d skipped  (%d total)\n", t->passed,
	       t->failed, t->skipped, t->total);

	if (machine && machine[0] && strcmp(machine, "0") != 0) {
		printf("JNL_TEST_RESULT %d %d %d %d\n", t->passed, t->failed,
		       t->skipped, t->total);
	}

	return t->failed == 0 ? 0 : 1;
}

//
// Internal assertion helpers
//

static inline void jnl_check_at(bool ok, const char *expr, const char *file,
                                int line)
{
	if (!ok)
		jnl_test_fail_at(file, line, "expected %s", expr);
}

static inline void jnl_check_msg_at(bool ok, const char *file, int line,
                                    const char *fmt, ...)
{
	va_list args;
	char msg[JNL_TEST_MSG_CAP];

	if (ok)
		return;

	va_start(args, fmt);
	vsnprintf(msg, sizeof(msg), fmt, args);
	va_end(args);

	jnl_test_fail_at(file, line, "%s", msg);
}

static inline void jnl_eq_i32_at(int a, int b, const char *a_expr,
                                 const char *b_expr, const char *file, int line)
{
	if (a != b) {
		jnl_test_fail_at(file, line, "expected %s == %s, got %d != %d", a_expr,
		                 b_expr, a, b);
	}
}

static inline void jnl_eq_u64_at(unsigned long long a, unsigned long long b,
                                 const char *a_expr, const char *b_expr,
                                 const char *file, int line)
{
	if (a != b) {
		jnl_test_fail_at(file, line, "expected %s == %s, got %llu != %llu",
		                 a_expr, b_expr, a, b);
	}
}

static inline void jnl_eq_ptr_at(const void *a, const void *b,
                                 const char *a_expr, const char *b_expr,
                                 const char *file, int line)
{
	if (a != b) {
		jnl_test_fail_at(file, line, "expected %s == %s, got %p != %p", a_expr,
		                 b_expr, a, b);
	}
}

static inline void jnl_null_at(const void *p, const char *expr,
                               const char *file, int line)
{
	if (p) {
		jnl_test_fail_at(file, line, "expected %s == NULL, got %p", expr, p);
	}
}

static inline void jnl_not_null_at(const void *p, const char *expr,
                                   const char *file, int line)
{
	if (!p) {
		jnl_test_fail_at(file, line, "expected %s != NULL", expr);
	}
}

static inline void jnl_near_f64_at(double a, double b, double eps,
                                   const char *a_expr, const char *b_expr,
                                   const char *eps_expr, const char *file,
                                   int line)
{
	double diff = fabs(a - b);

	if (diff > eps) {
		jnl_test_fail_at(file, line,
		                 "expected %s ~= %s within %s, got %.17g vs %.17g "
		                 "(diff %.17g > %.17g)",
		                 a_expr, b_expr, eps_expr, a, b, diff, eps);
	}
}

static inline void jnl_str_eq_at(const char *a, const char *b,
                                 const char *a_expr, const char *b_expr,
                                 const char *file, int line)
{
	bool equal = false;

	if (!a && !b) {
		equal = true;
	} else if (a && b) {
		equal = strcmp(a, b) == 0;
	}

	if (!equal) {
		jnl_test_fail_at(file, line, "expected %s == %s, got \"%s\" != \"%s\"",
		                 a_expr, b_expr, a ? a : "(null)", b ? b : "(null)");
	}
}

//
// Public surface
//

#define JNL_TEST(t, fn) jnl_test_run((t), #fn, (fn))

#define JNL_SKIP_TEST(t, name) jnl_test_skip((t), (name))

#define FAIL(...) jnl_test_fail_at(__FILE__, __LINE__, __VA_ARGS__)

#define CHECK(expr) jnl_check_at((expr), #expr, __FILE__, __LINE__)

#define CHECK_MSG(expr, ...)                                                   \
	jnl_check_msg_at((expr), __FILE__, __LINE__, __VA_ARGS__)

#define EQ_I32(a, b)                                                           \
	jnl_eq_i32_at((int)(a), (int)(b), #a, #b, __FILE__, __LINE__)

#define EQ_U64(a, b)                                                           \
	jnl_eq_u64_at((unsigned long long)(a), (unsigned long long)(b), #a, #b,    \
	              __FILE__, __LINE__)

#define EQ_PTR(a, b)                                                           \
	jnl_eq_ptr_at((const void *)(a), (const void *)(b), #a, #b, __FILE__,      \
	              __LINE__)

#define NULL_PTR(p) jnl_null_at((const void *)(p), #p, __FILE__, __LINE__)

#define NOT_NULL(p) jnl_not_null_at((const void *)(p), #p, __FILE__, __LINE__)

#define NEAR_F64(a, b, eps)                                                    \
	jnl_near_f64_at((double)(a), (double)(b), (double)(eps), #a, #b, #eps,     \
	                __FILE__, __LINE__)

#define STR_EQ(a, b) jnl_str_eq_at((a), (b), #a, #b, __FILE__, __LINE__)

#endif
