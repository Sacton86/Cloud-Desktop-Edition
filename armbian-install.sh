#!/usr/bin/env bash
# armbian-install.sh — Impact LED Signs · VSN Cloud Player · Armbian/ARM Installer
#
# Designed for: Armbian Desktop (XFCE) on Orange Pi Zero 3W / ARM64
# Key differences vs install.sh:
#   - python3-opencv installed via apt (avoids 20-min ARM pip compilation)
#   - Defaults to fullscreen=true (kiosk device)
#   - Adds XFCE .desktop autostart as reliable fallback alongside systemd service
#   - SDL_VIDEODRIVER=x11 set explicitly for ARM boards
#
# Non-interactive mode — set before running:
#   VSN_TERMINAL_ID  VSN_TERMINAL_SECRET  VSN_CMS_SERVER
#   VSN_WIDTH  VSN_HEIGHT  VSN_FULLSCREEN

set -euo pipefail

# ── ANSI colours ────────────────────────────────────────────────
RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
CY="\033[36m"; CYB="\033[1;36m"; YL="\033[33m"
GR="\033[32m"; RD="\033[31m"; WH="\033[97m"

hr()      { echo -e "${DIM}${CY}  ─────────────────────────────────────────────────────────────${RESET}"; }
section() { echo; echo -e "${CYB}  ◈  $1${RESET}"; hr; }
ok()      { echo -e "${GR}  ✔  ${RESET}$1"; }
info()    { echo -e "${CY}  ·  ${RESET}$1"; }
warn()    { echo -e "${YL}  ⚠  ${RESET}$1"; }
err()     { echo -e "${RD}  ✘  ${RESET}$1" >&2; }

print_banner() {
    echo
    echo -e "${CYB}"
    echo '   ██╗███╗   ███╗██████╗  █████╗  ██████╗████████╗'
    echo '   ██║████╗ ████║██╔══██╗██╔══██╗██╔════╝╚══██╔══╝'
    echo '   ██║██╔████╔██║██████╔╝███████║██║        ██║   '
    echo '   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║        ██║   '
    echo '   ██║██║ ╚═╝ ██║██║     ██║  ██║╚██████╗   ██║   '
    echo '   ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝   ╚═╝   '
    echo -e "${RESET}"
    echo -e "${WH}         ██╗     ███████╗██████╗      ███████╗██╗ ██████╗ ███╗   ██╗███████╗${RESET}"
    echo -e "${WH}         ██║     ██╔════╝██╔══██╗     ██╔════╝██║██╔════╝ ████╗  ██║██╔════╝${RESET}"
    echo -e "${WH}         ██║     █████╗  ██║  ██║     ███████╗██║██║  ███╗██╔██╗ ██║███████╗${RESET}"
    echo -e "${WH}         ██║     ██╔══╝  ██║  ██║     ╚════██║██║██║   ██║██║╚██╗██║╚════██║${RESET}"
    echo -e "${WH}         ███████╗███████╗██████╔╝     ███████║██║╚██████╔╝██║ ╚████║███████║${RESET}"
    echo -e "${WH}         ╚══════╝╚══════╝╚═════╝      ╚══════╝██║ ╚═════╝ ╚═╝  ╚═══╝╚══════╝${RESET}"
    echo
    echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${CY}     Cloud Player Installer  ·  Impact LED Signs  ·  Armbian/ARM${RESET}"
    echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
    echo
}

# ── Root check ───────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    print_banner
    err "This installer must be run as root."
    echo -e "     ${DIM}Try:  sudo bash armbian-install.sh${RESET}"
    echo
    exit 1
fi

print_banner

# ── Determine service user & home ───────────────────────────────
SERVICE_USER="${SUDO_USER:-$USER}"
SERVICE_HOME=$(getent passwd "$SERVICE_USER" | cut -d: -f6)
if [[ -z "$SERVICE_HOME" ]]; then
    err "Could not determine home directory for user '${SERVICE_USER}'."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"

echo -e "${DIM}  Install directory :${RESET}  ${WH}${INSTALL_DIR}${RESET}"
echo -e "${DIM}  Running as user   :${RESET}  ${WH}${SERVICE_USER}${RESET}"
echo -e "${DIM}  Home directory    :${RESET}  ${WH}${SERVICE_HOME}${RESET}"
hr

# ── Config helper ────────────────────────────────────────────────
prompt_if_empty() {
    local var_name="$1" label="$2" default_val="${3:-}" silent="${4:-no}"
    local current_val="${!var_name:-}"
    if [[ -z "$current_val" ]]; then
        local prompt_str
        if [[ -n "$default_val" ]]; then
            prompt_str="$(echo -e "  ${YL}?${RESET}  ${label} ${DIM}[${default_val}]${RESET}: ")"
        else
            prompt_str="$(echo -e "  ${YL}?${RESET}  ${label}: ")"
        fi
        if [[ "$silent" == "yes" ]]; then
            read -rsp "$prompt_str" current_val; echo
        else
            read -rp "$prompt_str" current_val
        fi
        [[ -z "$current_val" && -n "$default_val" ]] && current_val="$default_val"
        printf -v "$var_name" '%s' "$current_val"
    else
        if [[ "$silent" == "yes" ]]; then
            info "${label}: ${DIM}[provided via environment]${RESET}"
        else
            info "${label}: ${WH}${!var_name}${RESET}"
        fi
    fi
}

# ── Gather configuration ─────────────────────────────────────────
section "Device Configuration"
echo -e "  ${DIM}Enter your device and Cloud+ credentials below.${RESET}"
echo -e "  ${DIM}Press Enter to accept the value shown in [brackets].${RESET}"
echo

prompt_if_empty VSN_TERMINAL_ID      "Terminal ID"
prompt_if_empty VSN_TERMINAL_SECRET  "Terminal Secret"              ""      "yes"
prompt_if_empty VSN_CMS_SERVER       "Cloud+ server URL"            "https://access.impactledsigns.com/"

section "Display Settings"
prompt_if_empty VSN_WIDTH       "Display width  (pixels)"      "1920"
prompt_if_empty VSN_HEIGHT      "Display height (pixels)"      "1080"
prompt_if_empty VSN_FULLSCREEN  "Fullscreen mode (true/false)"  "true"

[[ "${VSN_FULLSCREEN,,}" == "true" || "$VSN_FULLSCREEN" == "1" ]] \
    && FULLSCREEN_JSON="true" || FULLSCREEN_JSON="false"

echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CY}     Beginning installation…${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"

# ── [1/5] System dependencies ────────────────────────────────────
section "[1/5]  System Dependencies"
info "Updating package index…"
apt-get update -qq

info "Installing system packages…"
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-pygame \
    python3-opencv \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-ttf-dev \
    libsdl2-mixer-dev \
    git \
    jq \
    curl 2>/dev/null || true

# Second pass in case of transient failures
apt-get install -y --no-install-recommends jq curl 2>/dev/null || true
ok "System packages installed."
info "Using python3-opencv from apt — skips 20-min ARM compilation."

# ── [2/5] Python requirements ────────────────────────────────────
section "[2/5]  Python Requirements"
info "Installing Python packages (opencv excluded — installed via apt)…"

# Filter out opencv-python* since we installed the apt package
TMP_REQS=$(mktemp)
grep -vi 'opencv' "$INSTALL_DIR/requirements.txt" > "$TMP_REQS" || true

# --break-system-packages required on Debian 12+ (Armbian Bookworm)
if pip3 install --help 2>&1 | grep -q 'break-system-packages'; then
    pip3 install --break-system-packages -r "$TMP_REQS"
else
    pip3 install -r "$TMP_REQS"
fi

rm -f "$TMP_REQS"
ok "Python packages installed."

# ── [3/5] Write config ───────────────────────────────────────────
section "[3/5]  Player Configuration"
CONFIG_PATH="$INSTALL_DIR/player_config.json"

if command -v jq &>/dev/null; then
    jq -n \
        --argjson width    "$VSN_WIDTH" \
        --argjson height   "$VSN_HEIGHT" \
        --argjson fs       "$FULLSCREEN_JSON" \
        --arg    server    "$VSN_CMS_SERVER" \
        --arg    tid       "$VSN_TERMINAL_ID" \
        --arg    tsecret   "$VSN_TERMINAL_SECRET" \
        '{
            width:        $width,
            height:       $height,
            fullscreen:   $fs,
            fit_mode:     "native",
            fps:          60,
            bar_color:    "0xFF000000",
            loop:         true,
            show_hud:     false,
            last_dir:     "",
            brightness:   100,
            timezone:     "",
            locale_code:  "",
            cms_enabled:  true,
            cms_server:   $server,
            cms_username: $tid,
            cms_password: $tsecret,
            cms_interval: 30,
            cms_dl_dir:   ""
        }' > "$CONFIG_PATH"
else
    escape_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    printf '{
  "width": %s,
  "height": %s,
  "fullscreen": %s,
  "fit_mode": "native",
  "fps": 60,
  "bar_color": "0xFF000000",
  "loop": true,
  "show_hud": false,
  "last_dir": "",
  "brightness": 100,
  "timezone": "",
  "locale_code": "",
  "cms_enabled": true,
  "cms_server": "%s",
  "cms_username": "%s",
  "cms_password": "%s",
  "cms_interval": 30,
  "cms_dl_dir": ""
}\n' \
        "$VSN_WIDTH" "$VSN_HEIGHT" "$FULLSCREEN_JSON" \
        "$(escape_json "$VSN_CMS_SERVER")" \
        "$(escape_json "$VSN_TERMINAL_ID")" \
        "$(escape_json "$VSN_TERMINAL_SECRET")" > "$CONFIG_PATH"
fi

chown "$SERVICE_USER:$SERVICE_USER" "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"
ok "Config written  →  ${CONFIG_PATH}"

mkdir -p "$INSTALL_DIR/downloads"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/downloads"
ok "Downloads dir   →  ${INSTALL_DIR}/downloads"

# ── [4/6] Autostart setup ────────────────────────────────────────
section "[4/6]  Autostart"

# -- Systemd user service (handles crash-restart and manual control) --
SYSTEMD_USER_DIR="$SERVICE_HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

cat > "$SYSTEMD_USER_DIR/vsn_player.service" << SVCEOF
[Unit]
Description=VSN LED Sign Player
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
Environment=DISPLAY=:0
Environment=XAUTHORITY=${SERVICE_HOME}/.Xauthority
Environment=SDL_VIDEODRIVER=x11
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/player.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vsn_player

[Install]
WantedBy=graphical-session.target
SVCEOF

chown -R "$SERVICE_USER:$SERVICE_USER" "$SERVICE_HOME/.config/systemd"
ok "Systemd service  →  ${SYSTEMD_USER_DIR}/vsn_player.service"

# -- XFCE .desktop autostart (reliable fallback on Armbian XFCE/LightDM) --
# Triggers the systemd service via the desktop session, so only one instance runs.
XFCE_AUTOSTART_DIR="$SERVICE_HOME/.config/autostart"
mkdir -p "$XFCE_AUTOSTART_DIR"

cat > "$XFCE_AUTOSTART_DIR/vsn_player.desktop" << DESKEOF
[Desktop Entry]
Type=Application
Name=VSN LED Sign Player
Comment=Impact LED Signs Cloud+ Player
Exec=systemctl --user start vsn_player
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
DESKEOF

chown -R "$SERVICE_USER:$SERVICE_USER" "$XFCE_AUTOSTART_DIR"
ok "XFCE autostart   →  ${XFCE_AUTOSTART_DIR}/vsn_player.desktop"

# -- Disable screen blanking (sign player should never sleep) --
XPROFILE="$SERVICE_HOME/.xprofile"
if ! grep -q 'xset s off' "$XPROFILE" 2>/dev/null; then
    cat >> "$XPROFILE" << 'XPEOF'

# Disable screen blanking for sign player
xset s off
xset -dpms
xset s noblank
XPEOF
    chown "$SERVICE_USER:$SERVICE_USER" "$XPROFILE"
    ok "Screen blanking  →  disabled in ~/.xprofile"
fi

loginctl enable-linger "$SERVICE_USER"
ok "Linger enabled for '${SERVICE_USER}'  (autostart on boot)"

# ── [5/6] Enable & start ─────────────────────────────────────────
section "[5/6]  Starting Service"
XDG_RUNTIME_DIR="/run/user/$(id -u "$SERVICE_USER")"
export XDG_RUNTIME_DIR

run_as_user() {
    sudo -u "$SERVICE_USER" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        systemctl --user "$@"
}

run_as_user daemon-reload
run_as_user enable vsn_player
run_as_user start vsn_player \
    && ok "Service started." \
    || warn "Service start deferred — no display during install. Player will start automatically on next login/reboot."

# ── [6/6] Auto-updater (daily systemd timer) ─────────────────────
section "[6/6]  Auto-updater"

cat > /etc/systemd/system/vsn_updater.service << UPDEOF
[Unit]
Description=VSN Cloud Player Auto-updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=SUDO_USER=${SERVICE_USER}
Environment=INSTALL_DIR=${INSTALL_DIR}
ExecStart=/bin/bash ${INSTALL_DIR}/updater.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vsn_updater
UPDEOF

cat > /etc/systemd/system/vsn_updater.timer << TMREOF
[Unit]
Description=VSN Cloud Player daily update check

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=600
Persistent=true

[Install]
WantedBy=timers.target
TMREOF

systemctl daemon-reload
systemctl enable vsn_updater.timer
systemctl start vsn_updater.timer
ok "Auto-updater      →  daily at 03:00  (± 10 min)"

# ── Summary ──────────────────────────────────────────────────────
echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GR}${BOLD}     ✔  Installation complete!${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo
echo -e "  ${DIM}Terminal ID   :${RESET}  ${WH}${VSN_TERMINAL_ID}${RESET}"
echo -e "  ${DIM}Display       :${RESET}  ${WH}${VSN_WIDTH} × ${VSN_HEIGHT}  (fullscreen: ${FULLSCREEN_JSON})${RESET}"
echo -e "  ${DIM}Cloud+ server :${RESET}  ${WH}${VSN_CMS_SERVER}${RESET}"
echo -e "  ${DIM}Service user  :${RESET}  ${WH}${SERVICE_USER}${RESET}"
echo -e "  ${DIM}Config file   :${RESET}  ${WH}${CONFIG_PATH}${RESET}"
echo
echo -e "  ${DIM}Useful commands:${RESET}"
echo -e "    ${CY}journalctl --user -u vsn_player -f${RESET}    ${DIM}# live log${RESET}"
echo -e "    ${CY}systemctl --user status vsn_player${RESET}    ${DIM}# service status${RESET}"
echo -e "    ${CY}systemctl --user restart vsn_player${RESET}   ${DIM}# restart player${RESET}"
echo -e "    ${CY}systemctl --user stop vsn_player${RESET}      ${DIM}# stop player${RESET}"
echo -e "    ${CY}systemctl status vsn_updater.timer${RESET}    ${DIM}# updater schedule${RESET}"
echo -e "    ${CY}sudo bash ${INSTALL_DIR}/updater.sh${RESET}   ${DIM}# manual update${RESET}"
echo
echo -e "  ${DIM}Note: Player starts automatically on login/reboot.${RESET}"
echo -e "  ${DIM}      Updates check daily at 03:00 via systemd timer.${RESET}"
echo -e "  ${DIM}      Screen blanking disabled in ~/.xprofile.${RESET}"
echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${DIM}              Impact LED Signs  ·  impactledsigns.com${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo
