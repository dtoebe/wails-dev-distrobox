# wails-dev-distrobox

A Distrobox container image for [Wails v3](https://v3alpha.wails.io/) development —
desktop (GTK4 + WebKitGTK 6.0) **and** Android (SDK, NDK, emulator) — on Ubuntu 26.10.

Built and verified against Wails v3.1.0 on a Fedora/Kinoite (ublue Aurora) host with
podman 5.8 and distrobox 1.8.

> **AI-generated repository.** Every file here — the `Containerfile`, the
> `android-dev.sh` profile, the `wails3-dev` wrapper and this README — was
> written by an AI agent (Hermes Agent, Nous Research) working under the repo
> owner's direction. The agent had shell access to the owner's machine and
> validated each step by really running it: `podman build`, `distrobox create`,
> `wails3 doctor`, `wails3 build`, booting the emulator and installing and
> launching the APK. Review it yourself before trusting it on your own machine;
> no human has line-by-line reviewed the build instructions, and the
> version numbers will drift as upstreams update.

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

Environment variables are set by `/etc/profile.d/android-dev.sh`
(`ANDROID_HOME`, `ANDROID_USER_HOME`, `ANDROID_AVD_HOME`, `JAVA_HOME`, `GOPATH`,
`GOCACHE`) so all SDK state stays inside the container.

## Requirements

* podman (or docker) and distrobox >= 1.8
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
