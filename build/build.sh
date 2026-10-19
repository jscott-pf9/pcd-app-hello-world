#!/usr/bin/env bash
# Build dist/hello-world-<version>.qcow2 and its .sha256 from the stock Alpine cloud image.
# Needs: curl, qemu-img, virt-customize, virt-sysprep, virt-sparsify (libguestfs-tools).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION=$(cat VERSION)
ALPINE_BRANCH=3.21
ALPINE_RELEASE=3.21.7
BASE=nocloud_alpine-${ALPINE_RELEASE}-x86_64-bios-cloudinit-r0.qcow2
BASE_URL=https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/releases/cloud
OUT=dist/hello-world-${VERSION}.qcow2

mkdir -p build/cache dist
if [ ! -f "build/cache/$BASE" ]; then
  echo "==> Downloading $BASE"
  curl -fL --progress-bar -o "build/cache/$BASE.part" "$BASE_URL/$BASE"
  curl -fsSL -o "build/cache/$BASE.sha512" "$BASE_URL/$BASE.sha512"
  (cd build/cache && echo "$(cut -d' ' -f1 "$BASE.sha512")  $BASE.part" | sha512sum -c --quiet)
  mv "build/cache/$BASE.part" "build/cache/$BASE"
fi

# libguestfs reads the host kernel; Ubuntu makes it root-only, so use sudo there.
G=""
if [ "$(id -u)" -ne 0 ] && [ ! -r "/boot/vmlinuz-$(uname -r)" ]; then
  echo "==> /boot/vmlinuz-$(uname -r) is root-only; running libguestfs steps with sudo"
  G=sudo
fi

WORK=$(mktemp -d)
trap '$G rm -rf "$WORK"' EXIT
cp "build/cache/$BASE" "$WORK/work.qcow2"

echo "==> Installing the app"
$G virt-customize -q -a "$WORK/work.qcow2" \
  --install busybox-extras \
  --mkdir /usr/share/hello-world \
  --upload VERSION:/usr/share/hello-world/VERSION \
  --upload appliance/hello-world:/usr/local/bin/hello-world \
  --upload appliance/hello-world.initd:/etc/init.d/hello-world \
  --upload appliance/99_pcd_datasource.cfg:/etc/cloud/cloud.cfg.d/99_pcd_datasource.cfg \
  --chmod 0755:/usr/local/bin/hello-world \
  --chmod 0755:/etc/init.d/hello-world \
  --run-command 'rc-update add hello-world default' \
  --run-command 'rm -rf /var/cache/apk/*'

echo "==> Resetting machine state (cloud-init, host keys, logs)"
$G virt-sysprep -q -a "$WORK/work.qcow2"

echo "==> Compressing"
$G virt-sparsify -q --compress "$WORK/work.qcow2" "$OUT"
[ -z "$G" ] || sudo chown "$(id -u):$(id -g)" "$OUT"
(cd dist && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")

echo "==> $OUT"
qemu-img info "$OUT" | grep -E 'virtual size|disk size'
cat "$OUT.sha256"
