# wails-dev-distrobox

A Distrobox container image for [Wails v3](https://v3alpha.wails.io/) development —
desktop (GTK4 + WebKitGTK 6.0) **and** Android (SDK, NDK, emulator) — on Ubuntu 26.10.

Built and verified against Wails v3.1.0 on a Fedora/Kinoite (ublue Aurora) host with
podman 5.8 and distrobox 1.8.

> **AI-generated repository.** Every file here — the `Containerfile`, the
> `android-dev.sh` profile, the `wails3-dev` wrapper and this README — was
> written by an AI agent (Hermes Agent, Nous Research) working under the repo
> owner's direction. It validated each step by really running it:
> `podman build`, `distrobox create`,
> `wails3 doctor`, `wails3 build`, booting the emulator and installing and
> launching the APK. Review it yourself before trusting it on your own machine.

## What's inside

| Component | Version |
|---|---|
| Ubuntu | 26.10 |
| Go | 1.27.3 (`/usr/local/go`) |
| wails3 | v3.1.0 (`/opt/gopath/bin`) |
| Node / npm | 24.19 / 11.16 |
| JDK | OpenJDK 21 (`/usr/lib/jvm/java-21-openjdk-amd64`) |
| GTK | 4.24 (`libgtk-4-dev`) + 3.24 (`-tags gtk3`) |
| WebKit | WebKitGTK 6.0 2.52 + WebKit2GTK 4.1 (legacy tag) |
| Android platform | android-36, build-tools 36.0.0 |
| Android NDK | 26.3.11579264 |
| Emulator | 37.2.13 + `system-images;android-36;google_apis;x86_64` |
| AVD | `wails_pixel7` (pixel_7, 4 GB RAM, host GPU) |
| Docker CLI | 29.9.3, client only → host's rootless podman API (cross-compilation) |

Environment variables are set by `/etc/profile.d/android-dev.sh`
(`ANDROID_HOME`, `ANDROID_USER_HOME`, `ANDROID_AVD_HOME`, `JAVA_HOME`, `GOPATH`,
`GOCACHE`) so SDK state stays inside the container. The one exception is `GOPATH`:
at runtime it is `$HOME/.local/share/wails3-dev/gopath`, a path in the shared home,
because the cross-compilation tasks bind-mount `$GOPATH/pkg/mod` into the
`wails-cross` container and the host engine must be able to see that exact path
(see [Cross-compilation](#cross-compilation-the-official-wails3-flow)). The
`wails3` CLI itself stays at `/opt/gopath/bin`, installed at image build time.

## Requirements

* podman (or docker) and distrobox >= 1.8
* the host's rootless podman API socket, for cross-compilation:
  `systemctl --user enable --now podman.socket` (see "Cross-compilation" below)
* `/dev/kvm` — the emulator needs it
* `/dev/dri` — the emulator uses the host GPU (see the SwiftShader note below)
* ~22 GB of image, plus a few GB for the emulator's userdata

## Build and create

```sh
podman build --network=host -t localhost/wails3-dev:26.10 -f Containerfile .

distrobox create --name wails3-dev --hostname wails3-dev \
  --image localhost/wails3-dev:26.10 \
  --additional-flags "--device /dev/kvm --volume /run/udev:/run/udev:ro --volume /dev/bus/usb:/dev/bus/usb"
```

`--device /dev/kvm` is required by the emulator. `/dev/bus/usb` plus the baked
`/etc/udev/rules.d/51-android.rules` are for adb against a physical device.

## Usage

```sh
distrobox enter wails3-dev --clean-path     # shell with the container's toolchain
```

Or drop [`wails3-dev`](wails3-dev) from this repo into `~/.local/bin` — it is
just that command as a wrapper:

```sh
wails3-dev
wails3-dev wails3 doctor
```

`--clean-path` matters: plain `distrobox enter` puts the *host* PATH first, so
`go`, `node`, `npm` and `wails3` resolve to host installations (mise, in the
author's case) instead of the container's. `--clean-path` resets PATH to the
container's FHS paths.

Inside the container:

```sh
wails3 init -n app -t vanilla && cd app
wails3 build                     # desktop: GTK4 + WebKitGTK 6.0
wails3 build -tags gtk3          # legacy GTK3 + WebKit2GTK 4.1
wails3 task android:run          # libwails.so (x86_64) + APK, install, launch
wails3 task android:logs         # logcat
wails3 task android:run:device   # physical device
```

`wails3 doctor` should report every dependency and `No issues found`.

## Cross-compilation (the official wails3 flow)

Wails v3's cross-platform build drives everything through `docker build` / `docker run`
against a `wails-cross` image (`wails3 task setup:docker`, then `wails3 build GOOS=darwin`).
This box has **no container engine of its own** — no dockerd, no nested podman. Instead the
image ships the static **docker CLI only**, and `/etc/profile.d/docker-client.sh` points it at
the **host's rootless podman API socket**, which distrobox exposes at
`/run/user/<uid>/podman/podman.sock`. The containers therefore run on the host, not in the box.

### Host prerequisite (once)

From this repo, on the host — no sudo needed:

```sh
./host-setup.sh
```

It does three things, all scoped to your user:

1. `systemctl --user enable --now podman.socket` — the rootless podman API the
   box's `docker` client talks to (`loginctl enable-linger "$USER"` if you want
   that socket present when you are not logged in).
2. Installs `~/.config/containers/wails3-dev-containers.conf`:
   `[containers] userns="keep-id"` and `label=false`.
3. Points that socket's service at the file with a drop-in
   (`~/.config/systemd/user/podman.service.d/wails3-dev-containers.conf`), so
   your normal `podman`/`distrobox` invocations are unaffected.

Why those two settings exist — both are needed by the generated Taskfiles:

* `userns="keep-id"`: Wails runs `docker run --rm ... alpine chown -R $(id -u):$(id -g) /app/bin`
  after building. Under podman's default rootless mapping, container uid 1000 is a
  *subuid*, so that chown re-owns your project's `bin/` to an unmapped uid and the
  following `mv` fails with `Permission denied`. With `keep-id`, container uid 1000
  *is* your uid and the chown is correct.
* `label=false`: the cross-compile steps bind-mount the project and the Go module
  cache from `$HOME` (`user_home_t`), which a SELinux-labelled container cannot
  write to — the build dies with `mkdir: cannot create directory 'bin': Permission
  denied`. Distrobox already runs this box itself with `label=disable` for the same
  reason.

Verify from inside the box — both should succeed with no extra environment:

```sh
docker info        # Server Version 5.8.x, Operating System = your host
wails3 doctor      # docker | *Docker version ..., (cross-compilation ready)
docker run --rm alpine id   # uid=1000(dtoebe) - proves keep-id is in effect
```

If `docker info` cannot connect, the host socket is not running or not visible:
`DOCKER_HOST` is only exported when `/run/user/<uid>/podman/podman.sock` exists.
To undo the host side: remove the containers.conf, remove the `podman.service.d`
drop-in, `systemctl --user daemon-reload`, and `systemctl --user disable --now
podman.socket`. Nothing else on the host is touched.

### Build

```sh
distrobox enter wails3-dev --clean-path          # or ~/.local/bin/wails3-dev
wails3 init -n app -t vanilla && cd app

wails3 task setup:docker                         # one-time: builds the wails-cross image (~800 MB)

wails3 build GOOS=darwin                         # macOS arm64
wails3 build GOOS=darwin GOARCH=amd64            # macOS Intel
wails3 task darwin:build:universal               # arm64 + amd64 combined
wails3 build GOOS=linux                          # native in the box (gcc), docker not involved
wails3 build GOOS=windows                        # native Go cross-compile, CGO off
wails3 build GOOS=windows GOARCH=arm64
```

Output lands in `bin/`. The cross image lands in the **host's** podman store, not the box:

```sh
podman images | grep wails-cross        # run this on the host
```

### Limits worth knowing

* **Projects must live under `$HOME`** (`/var/home/dtoebe/...`). `docker run -v $(pwd):/app` is
  resolved by the host engine against the *host* filesystem, and distrobox mounts `$HOME` at the
  same absolute path. A project under `/tmp` or `/opt` inside the box would mount the wrong (or
  no) directory.
* `GOOS=linux` and `GOOS=windows` builds need no docker at all (`gcc` and Go are in the box).
  Only darwin, and windows with `CGO_ENABLED=1`, use the `wails-cross` image.
* macOS binaries built this way are unsigned — sign them on a Mac or in CI before distributing.
* The taskfile's precondition is literally `docker info`, so its error
  `Docker is required for cross-compilation. Please install Docker.` means *the host socket is
  not up*, not that the docker CLI is missing.
* The image is tagged `wails-cross`; re-run `wails3 task setup:docker` after
  `wails3 update build-assets` if `build/docker/Dockerfile.cross` changes.
* Dockerfile features are limited to what podman's Docker-compatible API supports (verified with
  the official `Dockerfile.cross`, including its `COPY <<'EOF'` heredocs). BuildKit-only syntax
  is not available.
* The module cache the cross build uses is `~/.local/share/wails3-dev/gopath/pkg/mod` (mounted
  into the container), so the first build downloads modules once and later builds reuse them.

## Gotchas

These are why the image is not just `distrobox create --image ubuntu:26.10`.

**1. `systemd-tpm` / `tpm-udev` break distrobox's first-run init.**
The 26.10 base image ships them; their postinst chowns `/dev/tpm*` and fails
inside a container (exit 73). That aborts distrobox's init, so no user is
created and `distrobox enter` fails with
`unable to find user <user>: no matching entries in passwd file`.
The image removes both packages.

**2. The bundled SwiftShader segfaults during composition.**
`avdmanager` writes `hw.gpu.enabled=no` for non-interactively created AVDs,
which silently selects SwiftShader — and `qemu-system-x86_64-headless` then
dies with SIGSEGV in `emulator/lib64/gles_swiftshader/libGLESv2.so` right after
"Emulator is performing a full startup". It reproduces with
`-gpu swiftshader_indirect`, `-gpu off` and `-feature -Vulkan`, with and without
KVM. The AVD is therefore pinned to `hw.gpu.enabled=yes` / `hw.gpu.mode=host`,
which renders through `/dev/dri` and boots in ~30 s (also fine headless with
`-no-window`).

**3. Windowed emulator needs the Qt xcb plugin dependencies.**
Without `libxkbfile1` and the xcb extension libs it exits immediately with
`libxkbfile.so.1: cannot open shared object file`. They are installed in the
image.

**4. `android:run` right after a cold boot can have the app killed once** while
the guest is still settling. Re-run the task, or
`adb shell am start -n com.wails.app/com.wails.app.MainActivity`.

## Adapting to your own user

The image assumes host user `dtoebe`, uid/gid 1000, home `/var/home/dtoebe`.
For another user, change the "container user" block in the `Containerfile`:

```dockerfile
RUN groupmod -n <user> ubuntu \
 && usermod -l <user> -d <home> -s /bin/bash ubuntu \
 && echo '<user> ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/<user> \
 && chmod 0440 /etc/sudoers.d/<user> \
 && mkdir -p <home> && chown <uid>:<gid> <home>
```

plus the matching `chown dtoebe:1000 /opt` and `USER dtoebe` lines. The uid must
match your host uid so the bind-mounted `$HOME` is writable. Distrobox mounts
your real home over `<home>` at runtime, so anything written there won't
persist in the image.

## Verified

* `wails3 doctor` — all dependencies found, `No issues found`
* desktop: `wails3 build` links with no missing libraries and the window renders
* Android: `wails3 task android:run` cold-starts the emulator, builds
  `libwails.so` + debug APK, installs it, and the template UI renders in the
  emulator's WebView
* cross-compilation, inside `wails3-dev` on a Fedora/Kinoite host with SELinux
  enforcing: `wails3 task setup:docker` builds `wails-cross` through the podman
  API, then `wails3 build GOOS=darwin` (`Mach-O 64-bit x86_64`),
  `GOOS=darwin GOARCH=arm64` (`Mach-O 64-bit arm64`), `GOOS=windows`
  (`PE32+ executable (GUI) x86-64`) and `GOOS=linux` (`ELF 64-bit LSB`)
  all produce `bin/` artifacts owned by the box user
