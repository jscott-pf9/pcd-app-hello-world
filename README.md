# pcd-app-hello-world

The smallest app that follows the [PCD App Catalog appliance contract](../pcd-app-catalog/docs/APPLIANCE_CONTRACT.md). It exists to demo and test the catalog end to end, with no app logic to get in the way.

- **Image:** a 94 MiB qcow2 (214 MiB virtual disk, UEFI). It's the stock Alpine 3.21 UEFI cloud image plus one shell script, and runs on 1 vCPU / 512 MB.
- **First boot:** cloud-init writes `/etc/pcd-app/config.env` (the catalog's standard user-data). The `hello-world` service reads it, renders a page, and serves it with busybox `httpd` on port 80.
- **`GET /api/health`** returns `{"status":"ok","configured":true,…}`, which the catalog's health check polls.
- **The page** shows the greeting and colour chosen in the install form, plus every key the catalog wrote, so you can see exactly what an app receives.

## Layout

```
manifest.json                    catalog manifest (also copied into pcd-app-catalog/catalog/manifests/)
VERSION
appliance/hello-world            the app: read config.env -> render -> exec httpd
appliance/hello-world.initd      OpenRC service (after cloud-init)
appliance/99_pcd_datasource.cfg  cloud-init fix: Alpine 3.21 ships NoCloud-only, which ignores Nova's config drive
build/build.sh                   Alpine cloud image -> dist/hello-world-<version>.qcow2 + .sha256
build/test-local.sh              boot it in QEMU with an OpenStack config drive, check health and page
test/user-data.sample            user-data exactly as the catalog generates it
```

## Build and test

```bash
build/build.sh                 # ~30 s; libguestfs steps use sudo if /boot/vmlinuz is root-only (Ubuntu)
build/test-local.sh            # boots with test/user-data.sample; KEEP=1 leaves the VM up on :8089
```

`test-local.sh` attaches the user-data the way Nova does, on a config drive labelled `config-2`, so a passing local test exercises the same path a PCD deploy takes.

## Release

1. Bump `VERSION`, run `build/build.sh`, and update `image.source.tag`, `asset` and `checksum` in `manifest.json` from `dist/*.sha256`.
2. Create GitHub release `v<version>` and attach `dist/hello-world-<version>.qcow2`, its `.sha256`, and `manifest.json`. The catalog's **Check for updates** reads `manifest.json` from the latest release.
3. The release must be **public**: Glance downloads the asset itself (web-download), without credentials.
