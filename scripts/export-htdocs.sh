#!/usr/bin/env bash
set -euo pipefail

container="${1:-}"
dest="${2:-}"

if [ -z "$container" ] || [ -z "$dest" ]; then
  echo "Usage: $0 <build-container> <output-dir>" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$dest/htdocs"
docker cp "${container}:/build/qemu-system-x86_64.js" "$dest/htdocs/out.js"
for f in qemu-system-x86_64.wasm qemu-system-x86_64.worker.js qemu-system-x86_64.data load.js; do
  docker cp "${container}:/build/${f}" "$dest/htdocs/"
done

cp "$repo_root/samples/index.html" "$dest/htdocs/"
cp "$repo_root/samples/module.js" "$dest/htdocs/"
cp "$repo_root/samples/cc.conf" "$dest/"
