#!/usr/bin/env bash
# Install Docker on the Ubuntu 24.04 destination box so repair-mongo-copy.sh
# can run the legacy mongo:3.x images. Uses Ubuntu's own docker.io package
# (no third-party apt repo needed). Run: sudo ./install-docker.sh [user]
#   user  gets added to the docker group (default: the sudo caller)
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "run as root: sudo $0" >&2; exit 1; }
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || echo "warning: tested for Ubuntu 24.04, this is $PRETTY_NAME" >&2

if command -v docker >/dev/null; then
  echo "docker already installed: $(docker --version)"
else
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y docker.io
fi

systemctl enable --now docker

U=${1:-${SUDO_USER:-}}
if [[ -n $U && $U != root ]]; then
  usermod -aG docker "$U"
  echo "added $U to docker group. Log out and back in (or run: newgrp docker) before using docker without sudo."
fi

docker --version
docker run --rm hello-world >/dev/null && echo "docker works"
