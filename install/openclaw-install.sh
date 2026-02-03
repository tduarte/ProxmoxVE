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

msg_info "Configuring AI Provider API Keys (optional)"
OPENCLAW_ENV_FILE="/root/.openclaw/.env"
mkdir -p /root/.openclaw

read -r -s -p "${TAB3}OpenAI API Key (leave blank to skip): " OPENAI_API_KEY
echo
if [[ -n "$OPENAI_API_KEY" ]]; then
  echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >>"$OPENCLAW_ENV_FILE"
fi

read -r -s -p "${TAB3}Google Gemini API Key (leave blank to skip): " GEMINI_API_KEY
echo
if [[ -n "$GEMINI_API_KEY" ]]; then
  echo "GEMINI_API_KEY=${GEMINI_API_KEY}" >>"$OPENCLAW_ENV_FILE"
fi

read -r -s -p "${TAB3}Anthropic API Key (leave blank to skip): " ANTHROPIC_API_KEY
echo
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" >>"$OPENCLAW_ENV_FILE"
fi

if [[ -f "$OPENCLAW_ENV_FILE" ]]; then
  chmod 600 "$OPENCLAW_ENV_FILE"
fi
msg_ok "API key configuration completed"

msg_info "Starting OpenClaw onboarding"
if openclaw onboard --install-daemon; then
  msg_ok "OpenClaw onboarding completed"
else
  msg_error "OpenClaw onboarding failed. Re-run: openclaw onboard --install-daemon"
  exit 1
fi

msg_info "Configuring OpenClaw Gateway for Tailscale Funnel"
openclaw config set gateway.mode local
openclaw config set gateway.bind loopback
openclaw config set gateway.tailscale.mode funnel
openclaw config set gateway.tailscale.resetOnExit false

GATEWAY_AUTH_PASSWORD=""
while [[ -z "$GATEWAY_AUTH_PASSWORD" ]]; do
  read -r -s -p "${TAB3}Set a Gateway password (required for non-loopback access): " GATEWAY_AUTH_PASSWORD
  echo
  if [[ -z "$GATEWAY_AUTH_PASSWORD" ]]; then
    msg_warn "Gateway password cannot be empty."
    continue
  fi
  read -r -s -p "${TAB3}Confirm Gateway password: " GATEWAY_AUTH_PASSWORD_CONFIRM
  echo
  if [[ "$GATEWAY_AUTH_PASSWORD" != "$GATEWAY_AUTH_PASSWORD_CONFIRM" ]]; then
    msg_warn "Passwords do not match. Try again."
    GATEWAY_AUTH_PASSWORD=""
  fi
done

openclaw config set gateway.auth.mode password
openclaw config set gateway.auth.password "$GATEWAY_AUTH_PASSWORD"
msg_ok "Configured Gateway defaults"

if systemctl --user enable --now openclaw-gateway.service >/dev/null 2>&1; then
  msg_ok "Enabled OpenClaw Gateway user service"
else
  msg_warn "Could not enable the OpenClaw Gateway user service."
  msg_warn "If it doesn't start after reboot, run: systemctl --user enable --now openclaw-gateway.service"
  msg_warn "You may also need: loginctl enable-linger $USER"
fi

motd_ssh
customize
cleanup_lxc

if [[ "$ROOT_PW_SET" != "yes" ]]; then
  echo -e "${INFO}${YW}No root password was set. You can set one later with: ${CL}${BOLD}passwd${CL}"
fi
