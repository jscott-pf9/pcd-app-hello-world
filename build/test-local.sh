#!/usr/bin/env bash
# Boot the built image in QEMU the way Nova would: an OpenStack config drive (label config-2)
# carrying the catalog's user-data. Then check /api/health and the page.
#   build/test-local.sh [user-data-file]     (default: test/user-data.sample)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION=$(cat VERSION)
IMAGE=dist/hello-world-${VERSION}.qcow2
USER_DATA=${1:-test/user-data.sample}
PORT=${PORT:-8089}
RUN=test/run
[ -f "$IMAGE" ] || { echo "build first: build/build.sh" >&2; exit 1; }

rm -rf "$RUN" && mkdir -p "$RUN/cd/openstack/latest"
qemu-img create -q -f qcow2 -b "$(realpath "$IMAGE")" -F qcow2 "$RUN/disk.qcow2"
cp "$USER_DATA" "$RUN/cd/openstack/latest/user_data"
echo '{"uuid": "00000000-0000-4000-8000-000000000001", "hostname": "hello-world-test", "name": "hello-world-test"}' \
  > "$RUN/cd/openstack/latest/meta_data.json"
genisoimage -quiet -o "$RUN/config-drive.iso" -V config-2 -r -J "$RUN/cd"

echo "==> Booting (console: $RUN/console.log, http://127.0.0.1:$PORT/)"
qemu-system-x86_64 -enable-kvm -m 512 -smp 1 -display none -daemonize -pidfile "$RUN/qemu.pid" \
  -drive file="$RUN/disk.qcow2",if=virtio \
  -drive file="$RUN/config-drive.iso",if=virtio,format=raw,readonly=on \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:80 -device virtio-net-pci,netdev=n0 \
  -serial file:"$RUN/console.log"
trap '[ -n "${KEEP:-}" ] || kill "$(cat "$RUN/qemu.pid")" 2>/dev/null || true' EXIT

start=$(date +%s)
until curl -sf "http://127.0.0.1:$PORT/api/health" >/dev/null; do
  if [ $(( $(date +%s) - start )) -gt 180 ]; then echo "no health after 180s; see $RUN/console.log" >&2; exit 1; fi
  sleep 2
done
echo "==> Healthy after $(( $(date +%s) - start ))s"
curl -s "http://127.0.0.1:$PORT/api/health"
curl -s "http://127.0.0.1:$PORT/" | sed -n 's|.*<h1>\(.*\)</h1>.*|greeting: \1|p'
if [ -n "${KEEP:-}" ]; then echo "KEEP set: VM left running (pid $(cat "$RUN/qemu.pid"))"; fi
