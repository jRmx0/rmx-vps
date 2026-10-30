#!/bin/bash
# Build the whole server from empty in a throwaway Ubuntu 24.04 container
# (systemd + Docker inside), then check that a second run changes nothing and
# that --check sees a manual change. Needs Docker with --privileged.
#   ansible/test/container-test.sh
# Not covered: Let's Encrypt (no DNS), the swapfile, a real reboot, -e probe=on.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
NAME=rmx-test
IMAGE=rmx-test-base
trap 'docker rm -f -v "$NAME" >/dev/null 2>&1 || true' EXIT

ct() { docker exec "$NAME" bash -c "$*"; }

docker build -q -t "$IMAGE" - >/dev/null <<'DOCKERFILE'
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq systemd systemd-sysv dbus sudo git curl ca-certificates \
    python3 python3-apt ansible-core iproute2 iptables kmod openssh-server >/dev/null \
 && apt-get clean
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
DOCKERFILE

docker rm -f -v "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
	--tmpfs /run --tmpfs /run/lock -v /var/lib/docker "$IMAGE" >/dev/null
for _ in $(seq 30); do
	[[ $(ct 'systemctl is-system-running 2>/dev/null || true') =~ running|degraded ]] && break
	sleep 1
done

# The repo as a git clone at /opt/rmx-vps, owned by the admin user (what bootstrap.sh makes).
ct 'useradd --create-home --shell /bin/bash rmx; install -d -o rmx -g rmx /opt/rmx-vps'
tar -C "$REPO" --exclude=.git -cf - . | docker exec -i "$NAME" tar -C /opt/rmx-vps -xf -
ct 'chown -R rmx:rmx /opt/rmx-vps'
docker exec "$NAME" cp /opt/rmx-vps/ansible/test/vault.yml /opt/rmx-vps/ansible/group_vars/all/vault.yml

# The image drops its package lists after every apt run (docker-clean); a real VPS keeps them.
ct 'rm -f /etc/apt/apt.conf.d/docker-clean; apt-get update -qq; apt-cache policy unattended-upgrades | grep -q Candidate'

play() { ct "cd /opt/rmx-vps/ansible && ansible-playbook site.yml $*"; }

echo "== run 1: from empty"
play | tail -30
echo "== run 2: must change nothing"
second=$(play | tee /dev/stderr)
grep -Eq 'changed=0 .*failed=0' <<<"$second" || { echo "FAIL: second run changed something" >&2; exit 1; }
echo "== --check after a manual change must report it"
ct "sed -i 's/^X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config.d/00-rmx.conf"
third=$(play --check --diff | tee /dev/stderr)
grep -q 'X11Forwarding' <<<"$third" || { echo "FAIL: --check did not see the manual change" >&2; exit 1; }
echo "OK: built from empty, idempotent, drift visible"
