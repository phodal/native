#!/usr/bin/env bash
# Linux live-truth loop, end to end. Run from the repo root on the host:
#
#   tools/linux-truth/run-all.sh [image|up|sync|recon|drive|suites|all]
#
# What it does (container-side, repo mounted read-only at /src, all build
# output in the container-local /work volume):
#   image  - build the container image (Zig + GTK4 + WebKitGTK dev + Xvfb)
#   up     - start (or restart) the long-lived container and sync sources
#   sync   - rsync /src -> /work (run after local edits)
#   recon  - build every showcase app for Linux, launch under Xvfb, dump
#            snapshot/widgets/views + engine and X screenshots to /out
#   drive  - per-app interaction scenarios (clicks, text input, wheel
#            scrolling, resize incl. min-size probe) with screenshots
#   suites - engine suite, example suites, and the webview link check,
#            all on real Linux
#   all    - everything above, in order
#
# Artifacts land in the container's /out; copy them out with
#   docker cp native-sdk-linux-truth:/out <dest>
set -eu

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
image=native-sdk-linux-truth
container=native-sdk-linux-truth
step="${1:-all}"

build_image() {
  docker build -t "$image" "$here"
}

up() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume create linux-truth-work >/dev/null
  docker run -d --name "$container" \
    -v "$repo_root":/src:ro \
    -v linux-truth-work:/work \
    "$image" sleep infinity >/dev/null
  docker exec "$container" mkdir -p /out
  sync_sources
}

sync_sources() {
  docker exec "$container" bash /src/tools/linux-truth/sync.sh
}

recon() {
  docker exec "$container" bash /src/tools/linux-truth/recon.sh
}

drive() {
  docker exec "$container" bash /src/tools/linux-truth/drive.sh
}

suites() {
  docker exec -w /work "$container" zig build test
  docker exec -w /work "$container" zig build validate
  docker exec -w /work "$container" zig build test-webview-system-link -Dplatform=linux
  docker exec -w /work "$container" zig build test-examples-native
}

case "$step" in
  image) build_image ;;
  up) up ;;
  sync) sync_sources ;;
  recon) sync_sources; recon ;;
  drive) sync_sources; drive ;;
  suites) sync_sources; suites ;;
  all) build_image; up; recon; drive; suites ;;
  *) echo "usage: $0 [image|up|sync|recon|drive|suites|all]" >&2; exit 2 ;;
esac
