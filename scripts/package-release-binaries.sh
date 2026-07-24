#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <version> <target> <binary-dir> <output-dir> <python-runtime>" >&2
  exit 2
fi

version="$1"
target="$2"
binary_dir="$3"
output_dir="$4"
python_runtime="$5"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python_license="$repo_root/LICENSE-PYTHON"

if [[ ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
  echo "invalid release version: $version" >&2
  exit 1
fi

case "$target" in
  x86_64-unknown-linux-gnu)
    expected_os="Linux"
    expected_arch="x86_64"
    file_arch_pattern="x86-64"
    ;;
  aarch64-apple-darwin)
    expected_os="Darwin"
    expected_arch="arm64"
    file_arch_pattern="arm64"
    ;;
  *)
    echo "unsupported release target: $target" >&2
    exit 1
    ;;
esac

actual_os="$(uname -s)"
actual_arch="$(uname -m)"
if [[ "$actual_os" != "$expected_os" || "$actual_arch" != "$expected_arch" ]]; then
  echo "release target $target requires $expected_os/$expected_arch; got $actual_os/$actual_arch" >&2
  exit 1
fi

for binary in spel spel-client-gen; do
  binary_path="$binary_dir/$binary"
  if [[ ! -x "$binary_path" ]]; then
    echo "missing executable: $binary_path" >&2
    exit 1
  fi
  if ! file "$binary_path" | grep -q "$file_arch_pattern"; then
    echo "unexpected architecture for $binary_path: $(file "$binary_path")" >&2
    exit 1
  fi
done

if [[ ! -r "$python_runtime" ]]; then
  echo "missing Python runtime: $python_runtime" >&2
  exit 1
fi
if [[ ! -r "$python_license" ]]; then
  echo "missing Python license: $python_license" >&2
  exit 1
fi
runtime_name="$(basename "$python_runtime")"
if [[ ! "$runtime_name" =~ ^[0-9A-Za-z._+-]+$ ]]; then
  echo "invalid Python runtime name: $runtime_name" >&2
  exit 1
fi

bundle_name="spel-${version}-${target}"
archive_name="${bundle_name}.tar.gz"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

mkdir -p "$staging_dir/$bundle_name/lib" "$output_dir"
install -m 0755 "$binary_dir/spel" "$staging_dir/$bundle_name/spel"
install -m 0755 "$binary_dir/spel-client-gen" "$staging_dir/$bundle_name/spel-client-gen"
install -m 0755 "$python_runtime" "$staging_dir/$bundle_name/lib/$runtime_name"
install -m 0644 "$repo_root/README.md" "$staging_dir/$bundle_name/README.md"
install -m 0644 "$repo_root/LICENSE-APACHE-v2" "$staging_dir/$bundle_name/LICENSE-APACHE-v2"
install -m 0644 "$repo_root/LICENSE-MIT" "$staging_dir/$bundle_name/LICENSE-MIT"
install -m 0644 "$python_license" "$staging_dir/$bundle_name/LICENSE-PYTHON"
printf '%s\n' "$version" > "$staging_dir/$bundle_name/VERSION"

if [[ "$target" == aarch64-apple-darwin ]]; then
  codesign --force --sign - "$staging_dir/$bundle_name/lib/$runtime_name"
  codesign --force --sign - "$staging_dir/$bundle_name/spel"
fi

tar -C "$staging_dir" -czf "$output_dir/$archive_name" "$bundle_name"

(
  cd "$output_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive_name" > "${archive_name}.sha256"
  else
    shasum -a 256 "$archive_name" > "${archive_name}.sha256"
  fi
)
