#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <version> <target> <archive>" >&2
  exit 2
fi

version="$1"
target="$2"
archive="$3"
bundle_name="spel-${version}-${target}"
extract_dir="$(mktemp -d)"
trap 'rm -rf "$extract_dir"' EXIT

if [[ ! -s "$archive" ]]; then
  echo "missing release archive: $archive" >&2
  exit 1
fi

tar -C "$extract_dir" -xzf "$archive"
bundle="$extract_dir/$bundle_name"
spel="$bundle/spel"
client_gen="$bundle/spel-client-gen"

test -x "$spel"
test -x "$client_gen"
test -s "$bundle/LICENSE-PYTHON"
test "$(cat "$bundle/VERSION")" = "$version"

runtime_count=0
python_runtime=""
for candidate in "$bundle/lib"/*; do
  if [[ -f "$candidate" ]]; then
    python_runtime="$candidate"
    runtime_count=$((runtime_count + 1))
  fi
done
if [[ $runtime_count -ne 1 ]]; then
  echo "expected exactly one bundled Python runtime" >&2
  exit 1
fi
runtime_name="$(basename "$python_runtime")"

case "$target" in
  x86_64-unknown-linux-gnu)
    test "$(uname -s)" = Linux
    test "$(uname -m)" = x86_64
    file "$spel" | grep -q 'x86-64'
    file "$client_gen" | grep -q 'x86-64'
    readelf -d "$spel" |
      sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' |
      grep -Fxq "$runtime_name"
    readelf -d "$spel" |
      grep -E 'RPATH|RUNPATH' |
      grep -Fq "\$ORIGIN/lib"
    linkage="$(ldd "$spel")"
    if grep -q 'not found' <<<"$linkage"; then
      echo "$linkage" >&2
      exit 1
    fi
    grep -Fq "$python_runtime" <<<"$linkage"
    ;;
  aarch64-apple-darwin)
    test "$(uname -s)" = Darwin
    test "$(uname -m)" = arm64
    file "$spel" | grep -q 'arm64'
    file "$client_gen" | grep -q 'arm64'
    portable_link="@executable_path/lib/$runtime_name"
    load_commands="$(otool -L "$spel")"
    grep -Fq "$portable_link" <<<"$load_commands"
    if grep -E '/Library/Frameworks/Python|/opt/(homebrew|hostedtoolcache).*[Pp]ython' \
      <<<"$load_commands"; then
      echo "$load_commands" >&2
      exit 1
    fi
    rpaths="$(
      otool -l "$spel" |
        awk '$1 == "cmd" && $2 == "LC_RPATH" {
          getline
          getline
          print $2
        }'
    )"
    grep -Fxq '@executable_path/lib' <<<"$rpaths"
    if grep -E '/opt/(homebrew|hostedtoolcache)' <<<"$rpaths"; then
      echo "$rpaths" >&2
      exit 1
    fi
    codesign --verify "$spel"
    ;;
  *)
    echo "unsupported release target: $target" >&2
    exit 1
    ;;
esac

"$spel" init --help
"$client_gen" --help
