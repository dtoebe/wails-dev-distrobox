# Wails v3 / Android development environment (distrobox: wails3-dev)
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_USER_HOME=/opt/android-user-home
export ANDROID_AVD_HOME=/opt/android-user-home/avd
export ANDROID_EMULATOR_HOME=/opt/android-user-home
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export GOPATH=/opt/gopath
export GOMODCACHE=/opt/gopath/pkg/mod
export GOCACHE=/opt/gocache
case ":$PATH:" in
  *":/opt/gopath/bin:"*) ;;
  *) export PATH="/opt/gopath/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:$PATH" ;;
esac
