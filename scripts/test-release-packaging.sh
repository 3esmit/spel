#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    target="x86_64-unknown-linux-gnu"
    ;;
  Darwin/arm64)
    target="aarch64-apple-darwin"
    ;;
  *)
    echo "unsupported packaging-test host: $(uname -s)/$(uname -m)" >&2
    exit 1
    ;;
esac

mkdir -p "$temp_dir/bin" "$temp_dir/dist" "$temp_dir/extract"
true_binary="$(type -P true)"
if [[ ! -x "$true_binary" ]]; then
  echo "cannot locate an executable true command" >&2
  exit 1
fi
install -m 0755 "$true_binary" "$temp_dir/bin/spel"
install -m 0755 "$true_binary" "$temp_dir/bin/spel-client-gen"

"$repo_root/scripts/package-release-binaries.sh" \
  "0.0.0-test.1" \
  "$target" \
  "$temp_dir/bin" \
  "$temp_dir/dist" \
  "$true_binary" \
  "$repo_root/LICENSE-MIT"

archive="spel-0.0.0-test.1-${target}.tar.gz"
checksum="${archive}.sha256"

test -s "$temp_dir/dist/$archive"
test -s "$temp_dir/dist/$checksum"

(
  cd "$temp_dir/dist"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$checksum"
  else
    shasum -a 256 -c "$checksum"
  fi
)

tar -C "$temp_dir/extract" -xzf "$temp_dir/dist/$archive"
bundle="$temp_dir/extract/spel-0.0.0-test.1-${target}"

test -x "$bundle/spel"
test -x "$bundle/spel-client-gen"
test "$(cat "$bundle/VERSION")" = "0.0.0-test.1"
test -s "$bundle/README.md"
test -s "$bundle/LICENSE-APACHE-v2"
test -s "$bundle/LICENSE-MIT"
test -s "$bundle/LICENSE-PYTHON"
test -x "$bundle/lib/$(basename "$true_binary")"

actual_files="$(
  for path in "$bundle"/*; do
    if [[ -f "$path" ]]; then
      basename "$path"
    fi
  done | LC_ALL=C sort
)"
expected_files="$(printf '%s\n' \
  LICENSE-APACHE-v2 \
  LICENSE-MIT \
  LICENSE-PYTHON \
  README.md \
  VERSION \
  spel \
  spel-client-gen)"
[[ "$actual_files" == "$expected_files" ]]
