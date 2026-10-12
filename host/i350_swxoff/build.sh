#!/bin/sh
set -eu

kernel_release=6.8.0-138-generic
build_dir=/lib/modules/$kernel_release/build
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_dir=${IGB_SOURCE_DIR:-$script_dir/source}

if [ "$(uname -r)" != "$kernel_release" ]; then
	echo "error: running kernel is not $kernel_release" >&2
	exit 1
fi

test -d "$build_dir"
test "$(dpkg-query -W -f='${Version}' linux-headers-$kernel_release)" = \
	"6.8.0-138.138~22.04.1"
test "$(gcc-12 -dumpfullversion)" = "12.3.0"
test -f "$source_dir/Makefile"

exec make -C "$build_dir" M="$source_dir" modules
