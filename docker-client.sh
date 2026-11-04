# Docker CLI -> host rootless podman API (distrobox: wails3-dev)
#
# This box has no container engine of its own (no podman, no docker daemon, no
# podman-in-podman). The `docker` client baked into the image talks to the
# HOST's rootless podman API socket instead, which distrobox exposes inside the
# container under /run/user/<uid>. Containers then run on the real host.
#
# Host prerequisite (once), from the repo:
#   ./host-setup.sh
# It enables podman.socket and makes that socket's service use a containers.conf
# fragment with userns="keep-id" and label=false - both required by Wails'
# cross-compilation bind mounts and its chown-back-to-your-uid step.
#
# Wails v3 cross-compilation (wails3 task setup:docker, wails3 build GOOS=darwin)
# shells out to `docker build` / `docker run`, so this only has to make a
# Docker-compatible CLI + endpoint appear on PATH.
_uid=$(id -u)
for _dir in "${XDG_RUNTIME_DIR:-}" "/run/user/${_uid}" "/run/host/run/user/${_uid}"; do
  [ -n "$_dir" ] || continue
  if [ -S "${_dir}/podman/podman.sock" ]; then
    export DOCKER_HOST="unix://${_dir}/podman/podman.sock"
    break
  fi
done
unset _uid _dir
