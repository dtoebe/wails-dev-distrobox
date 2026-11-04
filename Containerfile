# wails3-dev : Ubuntu 26.10 distrobox image for Wails v3 desktop + Android development
# Build:  podman build -t localhost/wails3-dev:26.10 -f Containerfile .
# Create: distrobox create --name wails3-dev --image localhost/wails3-dev:26.10 \
#           --additional-flags "--device /dev/kvm --volume /run/udev:/run/udev:ro --volume /dev/bus/usb:/dev/bus/usb"
FROM docker.io/library/ubuntu:26.10

# NOTE on GOPATH below: it is build-time only. The wails3 CLI is installed into
# /opt/gopath/bin, but at runtime /etc/profile.d/android-dev.sh overrides GOPATH
# to a $HOME path, because Wails' cross-compile tasks bind-mount $GOPATH/pkg/mod
# and the host engine has to see that path too (see README, "Cross-compilation").
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=America/Denver \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_USER_HOME=/opt/android-user-home \
    ANDROID_AVD_HOME=/opt/android-user-home/avd \
    ANDROID_EMULATOR_HOME=/opt/android-user-home \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    GOPATH=/opt/gopath \
    GOMODCACHE=/opt/gopath/pkg/mod \
    GOCACHE=/opt/gocache

ARG GO_VERSION=1.27.3
ARG CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG API=36
ARG BUILD_TOOLS=36.0.0
ARG NDK_VERSION=26.3.11579264
ENV SYS_IMG="system-images;android-${API};google_apis;x86_64"

# ---- base fixes -------------------------------------------------------------
# The 26.10 base image ships systemd-tpm/tpm-udev whose postinst chowns /dev/tpm*
# and fails inside a container (exit 73), which aborts distrobox's init.
RUN mkdir -p /run/systemd/journal /usr/share/doc/tpm-udev; \
    dpkg --remove --force-all tpm-udev systemd-tpm; \
    dpkg --configure -a; \
    true

# ---- package sets -----------------------------------------------------------
# distrobox "basic packages" (so its first-run init has nothing to do) plus the
# Wails v3 / Android toolchain dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash apt-utils bash-completion bc bzip2 curl dialog diffutils findutils \
      gnupg hostname iproute2 iputils-ping keyutils less libcap2-bin libkrb5-3 \
      libnss-mdns libnss-myhostname libvte-2.91-0 locales lsof man-db manpages \
      mtr ncurses-base openssh-client passwd pigz pinentry-curses procps rsync \
      sudo tcpdump time traceroute tree tzdata unzip util-linux wget xauth \
      xz-utils zip \
      build-essential pkg-config git ca-certificates file jq \
      libgtk-4-dev libwebkitgtk-6.0-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
      libayatana-appindicator3-dev \
      nodejs npm openjdk-21-jdk \
      libgl1 libglu1-mesa libglx-mesa0 libegl1 libgbm1 libvulkan1 \
      mesa-vulkan-drivers libegl-mesa0 \
      libpulse0 libasound2t64 libnss3 libnspr4 \
      libx11-xcb1 libxcb1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
      libxcb-render-util0 libxcb-shape0 libxcb-xfixes0 libxcb-xinerama0 \
      libxcb-xkb1 libxcb-cursor0 libxkbcommon-x11-0 \
      libxcomposite1 libxdamage1 libxrandr2 libxi6 libxtst6 libxcursor1 \
      libxinerama1 fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

# ---- container user (uid/gid 1000 of the host user) ------------------------
# The base image already ships uid/gid 1000 as "ubuntu"; rename it in place.
# NOTE: "dtoebe" / /var/home/dtoebe are this maintainer's host user — see the
# "Adapting to your own user" section of README.md before building.
RUN groupmod -n dtoebe ubuntu \
 && usermod -l dtoebe -d /var/home/dtoebe -s /bin/bash ubuntu \
 && echo 'dtoebe ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dtoebe \
 && chmod 0440 /etc/sudoers.d/dtoebe \
 && mkdir -p /var/home/dtoebe && chown 1000:1000 /var/home/dtoebe

# ---- Go ---------------------------------------------------------------------
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
      | tar -C /usr/local -xzf - \
 && ln -sf /usr/local/go/bin/go /usr/local/bin/go \
 && ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
 && go version

ENV PATH=/opt/gopath/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ---- Android SDK ------------------------------------------------------------
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" "$ANDROID_USER_HOME/avd" "$GOPATH/bin" /opt/gocache \
 && curl -fsSL -o /tmp/cmdtools.zip "https://dl.google.com/android/repository/${CMDLINE_TOOLS}" \
 && unzip -q /tmp/cmdtools.zip -d /tmp \
 && mv /tmp/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
 && rm -f /tmp/cmdtools.zip \
 && chown -R dtoebe:1000 "$ANDROID_HOME" "$ANDROID_USER_HOME" "$GOPATH" /opt/gocache

USER dtoebe
RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true
RUN sdkmanager --install "platform-tools" "platforms;android-${API}" \
      "build-tools;${BUILD_TOOLS}" "ndk;${NDK_VERSION}" "emulator" "$SYS_IMG"

# AVD for the emulator (x86_64 host -> x86_64 system image)
# hw.gpu.mode set here is only a placeholder: the emulator graphics section at
# the bottom of this file re-pins hw.gpu.enabled/hw.gpu.mode to the host GPU,
# because the bundled SwiftShader segfaults (see README, gotcha 2).
RUN printf 'no\n' | avdmanager create avd -n wails_pixel7 -k "$SYS_IMG" -d pixel_7 --force \
 && cfg="$ANDROID_USER_HOME/avd/wails_pixel7.avd/config.ini" \
 && sed -i '/^hw.ramSize=/d;/^hw.gpu.mode=/d;/^disk.dataPartitionSize=/d' "$cfg" \
 && printf 'hw.ramSize=4096\nhw.gpu.mode=swiftshader_indirect\ndisk.dataPartitionSize=16G\n' >> "$cfg"

# ---- Wails v3 CLI -----------------------------------------------------------
RUN go install github.com/wailsapp/wails/v3/cmd/wails3@v3.1.0 && wails3 version

# ---- adb udev rules for physical devices ------------------------------------
USER root
RUN mkdir -p /etc/udev/rules.d && printf '%s\n' \
      'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"' \
      'SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", MODE="0666", GROUP="plugdev"' \
      'SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"' \
      'SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0666", GROUP="plugdev"' \
      'SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", MODE="0666", GROUP="plugdev"' \
      > /etc/udev/rules.d/51-android.rules \
 && chmod 0644 /etc/udev/rules.d/51-android.rules

COPY android-dev.sh /etc/profile.d/android-dev.sh
RUN chmod 0644 /etc/profile.d/android-dev.sh && chown -R dtoebe:1000 /opt

# ---- emulator graphics runtime ----------------------------------------------
# The windowed emulator loads Qt's xcb platform plugin, which needs libxkbfile
# and the xcb extension libs; without them it dies at once with
# "libxkbfile.so.1: cannot open shared object file".
RUN apt-get update && apt-get install -y --no-install-recommends \
      libxkbfile1 libxcb-randr0 libxcb-sync1 libxcb-xinput0 libxcb-dri3-0 \
      libxcb-present0 libxcb-glx0 libxcb-shm0 libxcb-util1 libxcb-xfixes0 \
 && rm -rf /var/lib/apt/lists/*

# hw.gpu.mode=host (real GPU via /dev/dri) instead of the default swiftshader:
# the bundled SwiftShader segfaults during composition on this kernel
# (SIGSEGV in libGLESv2.so right after "full startup"), with every backend
# (-gpu swiftshader_indirect/-gpu off/-feature -Vulkan). hw.gpu.enabled is set
# to "no" by avdmanager for AVDs created non-interactively, so force both.
RUN sed -i -e 's/^hw.gpu.enabled=.*/hw.gpu.enabled=yes/' \
           -e 's/^hw.gpu.mode=.*/hw.gpu.mode=host/' \
      "$ANDROID_USER_HOME/avd/wails_pixel7.avd/config.ini" \
 && chown -R dtoebe:1000 "$ANDROID_USER_HOME" \
 && grep -E '^hw.gpu' "$ANDROID_USER_HOME/avd/wails_pixel7.avd/config.ini"

# ---- Docker CLI (client only) for Wails cross-compilation --------------------
# The official cross-platform flow (wails3 task setup:docker, wails3 build
# GOOS=darwin ...) shells out to `docker build` / `docker run`. There is no
# engine inside this box and no podman-in-podman: the client talks to the HOST's
# rootless podman API socket (distrobox exposes it at /run/user/<uid>), so the
# containers actually run on the host. Containers still work because the box
# mounts $HOME at the same absolute path the host sees.
#
# Only the static docker CLI binary is installed here - no dockerd, no containerd,
# no docker.io apt chain, so nothing tries to start an engine in the container.
# /etc/profile.d/docker-client.sh exports DOCKER_HOST when that socket exists.
#
# Host side (once): run ./host-setup.sh from the repo - it enables
# podman.socket and points that socket's service at a containers.conf fragment
# with userns="keep-id" and label=false, both of which Wails' cross-compile
# bind mounts and chown step need. See README, "Cross-compilation".
ARG DOCKER_CLI_VERSION=29.9.3
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" \
      | tar -xz -C /tmp docker/docker \
 && install -m 0755 /tmp/docker/docker /usr/local/bin/docker \
 && rm -rf /tmp/docker \
 && docker --version

COPY docker-client.sh /etc/profile.d/docker-client.sh
RUN chmod 0644 /etc/profile.d/docker-client.sh

USER root
CMD ["/bin/bash"]
