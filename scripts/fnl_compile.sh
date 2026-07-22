#!/usr/bin/env bash
set -euo pipefail
lua_bin="$1"; fennel_dst="$2"; src="$3"; dst="$4"

if [[ -f "$dst" ]] && ! head -n1 "$dst" | grep -q '^-- \[nfnl\]'; then
	echo "refusing to overwrite handwritten file: $dst" >&2
	exit 1
fi

{
	echo "-- [nfnl] ${src}"
	"$lua_bin" scripts/fnl_compile.lua "$fennel_dst" "$src"
} > "$dst"
