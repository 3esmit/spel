#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <target> <spel-binary> <python-runtime>" >&2
  exit 2
fi

target="$1"
spel_binary="$2"
python_runtime="$3"
runtime_name="$(basename "$python_runtime")"

if [[ ! -x "$spel_binary" ]]; then
  echo "missing executable: $spel_binary" >&2
  exit 1
fi
if [[ ! -r "$python_runtime" ]]; then
  echo "missing Python runtime: $python_runtime" >&2
  exit 1
fi
if [[ ! "$runtime_name" =~ ^[0-9A-Za-z._+-]+$ ]]; then
  echo "invalid Python runtime name: $runtime_name" >&2
  exit 1
fi

case "$target" in
  x86_64-unknown-linux-gnu)
    command -v readelf >/dev/null
    needed="$(
      readelf -d "$spel_binary" |
        sed -n 's/.*Shared library: \[\(libpython[^]]*\)\].*/\1/p'
    )"
    if [[ "$needed" != "$runtime_name" ]]; then
      echo "Python dependency $needed does not match $runtime_name" >&2
      exit 1
    fi
    if ! readelf -d "$spel_binary" |
      grep -E 'RPATH|RUNPATH' |
      grep -Fq "\$ORIGIN/lib"; then
      echo "spel has no bundle-relative Linux runtime path" >&2
      exit 1
    fi
    ;;
  aarch64-apple-darwin)
    command -v codesign >/dev/null
    command -v install_name_tool >/dev/null
    command -v otool >/dev/null
    python_link="$(
      otool -L "$spel_binary" |
        awk 'NR > 1 && ($1 ~ /Python.*framework.*Python/ ||
                       $1 ~ /libpython/ ||
                       $1 ~ /^@executable_path\/lib\/Python/) {
          print $1
        }'
    )"
    if [[ -z "$python_link" || "$python_link" == *$'\n'* ]]; then
      echo "expected exactly one Python load command" >&2
      exit 1
    fi
    portable_link="@executable_path/lib/$runtime_name"
    if [[ "$python_link" != "$portable_link" ]]; then
      install_name_tool -change "$python_link" "$portable_link" "$spel_binary"
    fi
    codesign --force --sign - "$spel_binary"
    if ! otool -L "$spel_binary" |
      awk 'NR > 1 { print $1 }' |
      grep -Fxq "$portable_link"; then
      echo "spel has no bundle-relative Darwin Python dependency" >&2
      exit 1
    fi
    ;;
  *)
    echo "unsupported release target: $target" >&2
    exit 1
    ;;
esac
