#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

LAB_USER="labadmin"
PUBLIC_KEY="__PUBLIC_KEY__"

if ! id -u "$LAB_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups sudo "$LAB_USER"
else
  usermod --shell /bin/bash --append --groups sudo "$LAB_USER"
fi

install -d -m 700 -o "$LAB_USER" -g "$LAB_USER" "/home/$LAB_USER/.ssh"
printf '%s\n' "$PUBLIC_KEY" > "/home/$LAB_USER/.ssh/authorized_keys"
chmod 600 "/home/$LAB_USER/.ssh/authorized_keys"
chown "$LAB_USER:$LAB_USER" "/home/$LAB_USER/.ssh/authorized_keys"

cat > /etc/sudoers.d/labadmin <<'SUDOERS'
labadmin ALL=(ALL) NOPASSWD: ALL
SUDOERS
chmod 440 /etc/sudoers.d/labadmin
visudo --check --file=/etc/sudoers.d/labadmin

apt-get update
apt-get upgrade --yes
apt-get install --yes ca-certificates curl git jq rsync unzip htop unattended-upgrades

systemctl enable --now docker
if ! docker compose version >/dev/null 2>&1; then
  apt-get install --yes docker-compose-plugin
fi

install -d -m 755 -o root -g root /srv/labs
install -d -m 755 -o root -g root /srv/labs/datasets
install -d -m 755 -o root -g root /srv/labs/datasets/canonical
install -d -m 755 -o root -g root /srv/labs/datasets/manifests
install -d -m 755 -o root -g root /srv/labs/datasets/holdout
install -d -m 770 -o "$LAB_USER" -g "$LAB_USER" /srv/labs/projects
install -d -m 770 -o "$LAB_USER" -g "$LAB_USER" /srv/labs/projects/lab-a
install -d -m 770 -o "$LAB_USER" -g "$LAB_USER" /srv/labs/projects/lab-b

if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
if ! swapon --show=NAME --noheadings | grep -Fxq /swapfile; then
  swapon /swapfile
fi
if ! grep -qE '^/swapfile[[:space:]]' /etc/fstab; then
  printf '%s\n' '/swapfile none swap sw 0 0' >> /etc/fstab
fi

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable

systemctl enable --now apt-daily-upgrade.timer || true

printf '\n=== BOOTSTRAP SUMMARY ===\n'
id "$LAB_USER"
docker --version
docker compose version
ufw status verbose
swapon --show
df -h /srv/labs
ls -ld /srv/labs /srv/labs/datasets /srv/labs/projects/lab-a /srv/labs/projects/lab-b
