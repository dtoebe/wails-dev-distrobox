# Wails v3 / Android development environment (distrobox: wails3-dev)
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_USER_HOME=/opt/android-user-home
export ANDROID_AVD_HOME=/opt/android-user-home/avd
export ANDROID_EMULATOR_HOME=/opt/android-user-home
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# Go paths live under $HOME, not /opt. Wails' cross-compilation tasks mount
# $GOPATH/pkg/mod into the wails-cross container (`wails3 tool docker-mounts`),
# and that bind mount is resolved by the HOST engine against the host
# filesystem. A box-only path such as /opt/gopath does not exist on the host and
# cannot be created there without root, which fails the build with:
#   make cli opts(): making volume mountpoint for volume /opt/gopath/pkg/mod:
#   mkdir /opt/gopath: permission denied
# $HOME is bind-mounted at the same absolute path on both sides, so keeping
# GOPATH here makes the mount work and keeps the module cache across image
# rebuilds. The wails3 CLI itself stays at /opt/gopath/bin (installed at build
# time); $GOPATH/bin is where `go install` puts new binaries at runtime.
export GOPATH="$HOME/.local/share/wails3-dev/gopath"
export GOMODCACHE="$GOPATH/pkg/mod"
export GOCACHE=/opt/gocache
mkdir -p "$GOPATH/bin" "$GOMODCACHE" 2>/dev/null || true
case ":$PATH:" in
  *":$GOPATH/bin:"*) ;;
  *) export PATH="$GOPATH/bin:/opt/gopath/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:$PATH" ;;
esac
