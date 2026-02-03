#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: OpenClaw Community Scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://openclaw.im/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ROOT_PW_SET="no"
read -r -s -p "${TAB3}Set a root password now (leave blank to skip): " ROOT_PW
echo
if [[ -n "$ROOT_PW" ]]; then
  read -r -s -p "${TAB3}Confirm root password: " ROOT_PW_CONFIRM
  echo
  if [[ "$ROOT_PW" == "$ROOT_PW_CONFIRM" ]]; then
    echo "root:${ROOT_PW}" | chpasswd
    ROOT_PW_SET="yes"
    msg_ok "Root password updated"
  else
    msg_error "Passwords do not match. Skipping root password update."
  fi
fi

msg_info "Installing Dependencies"
$STD apt install -y ca-certificates curl gnupg lsb-release
msg_ok "Installed Dependencies"

msg_info "Installing Tailscale"
TS_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if [[ -z "$TS_CODENAME" ]]; then
  TS_CODENAME="bookworm"
fi
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${TS_CODENAME}.noarmor.gpg" | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${TS_CODENAME}.tailscale-keyring.list" | tee /etc/apt/sources.list.d/tailscale.list >/dev/null
$STD apt update
$STD apt install -y tailscale
systemctl enable -q --now tailscaled
msg_ok "Installed Tailscale"

read -r -p "${TAB3}Enter your Tailscale auth key (leave blank to skip): " TAILSCALE_AUTHKEY
if [[ -n "$TAILSCALE_AUTHKEY" ]]; then
  msg_info "Bringing Tailscale Up"
  if $STD tailscale up --authkey "$TAILSCALE_AUTHKEY" --hostname "$HOSTNAME"; then
    msg_ok "Tailscale is up"
  else
    msg_error "Tailscale failed to authenticate. You can run 'tailscale up' later."
  fi
else
  msg_info "Skipping Tailscale authentication"
fi

NODE_VERSION="22" setup_nodejs

msg_info "Installing OpenClaw"
$STD npm install -g openclaw@latest
msg_ok "Installed OpenClaw"

msg_info "Starting OpenClaw onboarding"
if openclaw onboard --install-daemon; then
  msg_ok "OpenClaw onboarding completed"
else
  msg_error "OpenClaw onboarding failed. Re-run: openclaw onboard --install-daemon"
  exit 1
fi

motd_ssh
customize
cleanup_lxc

if [[ "$ROOT_PW_SET" != "yes" ]]; then
  echo -e "${INFO}${YW}No root password was set. You can set one later with: ${CL}${BOLD}passwd${CL}"
fi
