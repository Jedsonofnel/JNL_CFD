#!/bin/sh

passed=0
failed_assertions=0
skipped=0
total=0
failed_bins=0

if [ "$#" -eq 0 ]; then
	printf "no C test binaries given\n" >&2
	exit 1
fi

for t in "$@"; do
	name=$(basename "$t")

	out=$(JNL_TEST_MACHINE=1 "$t" 2>&1)
	status=$?

	dots=$(printf "%s\n" "$out" | awk '/^[.FS]+$/ { print; exit }')
	result=$(printf "%s\n" "$out" | awk '/^JNL_TEST_RESULT / { print $2, $3, $4, $5; exit }')

	if [ -z "$result" ]; then
		printf "TEST %-28s FAILED exit=%d\n" "$name" "$status"

		if [ "$status" -gt 128 ]; then
			sig=$((status - 128))
			printf "  terminated by signal %d\n" "$sig"
		fi

		if [ -n "$out" ]; then
			printf "%s\n" "$out" | sed '/^JNL_TEST_RESULT /d'
		else
			printf "  no output captured; binary probably crashed before stdout flushed\n"
		fi

		failed_bins=$((failed_bins + 1))
		continue
	fi

	set -- $result
	p=$1
	f=$2
	s=$3
	n=$4

	passed=$((passed + p))
	failed_assertions=$((failed_assertions + f))
	skipped=$((skipped + s))
	total=$((total + n))

	if [ "$status" -eq 0 ]; then
		printf "TEST %-28s %-24s OK\n" "$name" "$dots"
	else
		printf "TEST %-28s %-24s FAILED\n" "$name" "$dots"
		printf "%s\n" "$out" | sed '/^JNL_TEST_RESULT /d'
		failed_bins=$((failed_bins + 1))
	fi
done

printf "\n%d passed  %d failed  %d skipped  (%d total)" \
	"$passed" "$failed_assertions" "$skipped" "$total"

if [ "$failed_bins" -gt 0 ]; then
	printf "  [%d failed test binary/binaries]" "$failed_bins"
fi

printf "\n"

exit 0
