#!/usr/bin/env bash
# install.sh — Impact LED Signs  ·  VSN Cloud Player  ·  Installer
#
# Non-interactive (bulk / env-var) mode — set before running:
#   VSN_TERMINAL_ID   VSN_TERMINAL_SECRET   VSN_CMS_SERVER
#   VSN_WIDTH   VSN_HEIGHT   VSN_FULLSCREEN
# ---------------------------------------------------------------

set -euo pipefail

# ── ANSI colours ────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

CY="\033[36m"       # cyan   — primary brand colour
CYB="\033[1;36m"    # cyan bold
YL="\033[33m"       # yellow — prompts / warnings
GR="\033[32m"       # green  — success
RD="\033[31m"       # red    — errors
WH="\033[97m"       # bright white

# ── helpers ─────────────────────────────────────────────────────
hr() { echo -e "${DIM}${CY}  ─────────────────────────────────────────────────────────────${RESET}"; }

section() {
    echo
    echo -e "${CYB}  ◈  $1${RESET}"
    hr
}

ok()   { echo -e "${GR}  ✔  ${RESET}$1"; }
info() { echo -e "${CY}  ·  ${RESET}$1"; }
warn() { echo -e "${YL}  ⚠  ${RESET}$1"; }
err()  { echo -e "${RD}  ✘  ${RESET}$1" >&2; }

# ── ASCII banner ─────────────────────────────────────────────────
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
    echo -e "${WH}         ╚══════╝╚══════╝╚═════╝      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝${RESET}"
    echo
    echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${CY}     Cloud Player Installer  ·  Impact LED Signs  ·  v1.0${RESET}"
    echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
    echo
}

# ── Root check ───────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    print_banner
    err "This installer must be run as root."
    echo -e "     ${DIM}Try:  sudo bash install.sh${RESET}"
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

# ── Resolve install directory ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR"

echo -e "${DIM}  Install directory :${RESET}  ${WH}${INSTALL_DIR}${RESET}"
echo -e "${DIM}  Running as user   :${RESET}  ${WH}${SERVICE_USER}${RESET}"
echo -e "${DIM}  Home directory    :${RESET}  ${WH}${SERVICE_HOME}${RESET}"
hr

# ── Config helper ────────────────────────────────────────────────
prompt_if_empty() {
    local var_name="$1"
    local label="$2"
    local default_val="${3:-}"
    local silent="${4:-no}"
    local current_val="${!var_name:-}"

    if [[ -z "$current_val" ]]; then
        local prompt_str
        if [[ -n "$default_val" ]]; then
            prompt_str="$(echo -e "  ${YL}?${RESET}  ${label} ${DIM}[${default_val}]${RESET}: ")"
        else
            prompt_str="$(echo -e "  ${YL}?${RESET}  ${label}: ")"
        fi

        if [[ "$silent" == "yes" ]]; then
            read -rsp "$prompt_str" current_val
            echo
        else
            read -rp "$prompt_str" current_val
        fi

        if [[ -z "$current_val" && -n "$default_val" ]]; then
            current_val="$default_val"
        fi
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
prompt_if_empty VSN_TERMINAL_SECRET  "Terminal Secret"           ""   "yes"
prompt_if_empty VSN_CMS_SERVER       "Cloud+ server URL"         "https://access.impactledsigns.com/"

section "Display Settings"
prompt_if_empty VSN_WIDTH       "Display width  (pixels)"   "1920"
prompt_if_empty VSN_HEIGHT      "Display height (pixels)"   "1080"
prompt_if_empty VSN_FULLSCREEN  "Fullscreen mode (true/false)" "false"

# Normalise fullscreen to JSON boolean
if [[ "${VSN_FULLSCREEN,,}" == "true" || "$VSN_FULLSCREEN" == "1" ]]; then
    FULLSCREEN_JSON="true"
else
    FULLSCREEN_JSON="false"
fi

echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CY}     Beginning installation…${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"

# ── [1/5] System dependencies ────────────────────────────────────
section "[1/5]  System Dependencies"
info "Updating package index…"
apt-get update -qq

info "Installing required packages…"
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-pygame \
    libsdl2-dev \
    git \
    jq 2>/dev/null || true

# second pass in case of transient failures
apt-get install -y --no-install-recommends jq 2>/dev/null || true
ok "System packages installed."

# ── [2/5] Python requirements ────────────────────────────────────
section "[2/5]  Python Requirements"
info "Installing Python packages from requirements.txt…"
pip3 install --break-system-packages -r "$INSTALL_DIR/requirements.txt"
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
            show_fps:     false,
            last_dir:     "",
            brightness:   100,
            timezone:     "",
            locale_code:  "",
            cms_enabled:  true,
            cms_server:   $server,
            cms_username: $tid,
            cms_password: $tsecret,
            cms_interval: 30,
            cms_dl_dir:   "",
            device_type:  "linux"
        }' > "$CONFIG_PATH"
else
    escape_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    ESC_SERVER=$(escape_json "$VSN_CMS_SERVER")
    ESC_TID=$(escape_json "$VSN_TERMINAL_ID")
    ESC_TSECRET=$(escape_json "$VSN_TERMINAL_SECRET")

    printf '{
  "width": %s,
  "height": %s,
  "fullscreen": %s,
  "fit_mode": "native",
  "fps": 60,
  "bar_color": "0xFF000000",
  "loop": true,
  "show_hud": false,
  "show_fps": false,
  "last_dir": "",
  "brightness": 100,
  "timezone": "",
  "locale_code": "",
  "cms_enabled": true,
  "cms_server": "%s",
  "cms_username": "%s",
  "cms_password": "%s",
  "cms_interval": 30,
  "cms_dl_dir": "",
  "device_type": "linux"
}\n' \
        "$VSN_WIDTH" "$VSN_HEIGHT" "$FULLSCREEN_JSON" \
        "$ESC_SERVER" "$ESC_TID" "$ESC_TSECRET" \
        > "$CONFIG_PATH"
fi

chown "$SERVICE_USER":"$SERVICE_USER" "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"
ok "Config written  →  ${CONFIG_PATH}"

DOWNLOADS_DIR="$INSTALL_DIR/downloads"
mkdir -p "$DOWNLOADS_DIR"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$DOWNLOADS_DIR"
ok "Downloads dir   →  ${DOWNLOADS_DIR}"

# ── [4/5] Systemd user service ───────────────────────────────────
section "[4/5]  System Service"
SYSTEMD_USER_DIR="$SERVICE_HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

SERVICE_SRC="$INSTALL_DIR/vsn_player.service"
SERVICE_DEST="$SYSTEMD_USER_DIR/vsn_player.service"

sed \
    -e "s|%h|$SERVICE_HOME|g" \
    -e "s|WorkingDirectory=.*|WorkingDirectory=$INSTALL_DIR|" \
    -e "s|ExecStart=.*|ExecStart=/usr/bin/python3 $INSTALL_DIR/player.py|" \
    "$SERVICE_SRC" > "$SERVICE_DEST"

chown -R "$SERVICE_USER":"$SERVICE_USER" "$SERVICE_HOME/.config/systemd"
ok "Service file    →  ${SERVICE_DEST}"

loginctl enable-linger "$SERVICE_USER"
ok "Linger enabled for '${SERVICE_USER}'  (autostart on boot)"

# ── [5/5] Enable & start ─────────────────────────────────────────
section "[5/5]  Starting Service"
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
run_as_user start vsn_player && ok "Service started." || warn "Service start deferred — display may not be up yet. It will start automatically on next login/boot."

# ── Summary ──────────────────────────────────────────────────────
echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GR}${BOLD}     ✔  Installation complete!${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo
echo -e "  ${DIM}Terminal ID  :${RESET}  ${WH}${VSN_TERMINAL_ID}${RESET}"
echo -e "  ${DIM}Display      :${RESET}  ${WH}${VSN_WIDTH} × ${VSN_HEIGHT}  (fullscreen: ${FULLSCREEN_JSON})${RESET}"
echo -e "  ${DIM}Cloud+ server :${RESET}  ${WH}${VSN_CMS_SERVER}${RESET}"
echo -e "  ${DIM}Service user :${RESET}  ${WH}${SERVICE_USER}${RESET}"
echo -e "  ${DIM}Config file  :${RESET}  ${WH}${CONFIG_PATH}${RESET}"
echo
echo -e "  ${DIM}Useful commands:${RESET}"
echo -e "    ${CY}journalctl --user -u vsn_player -f${RESET}   ${DIM}# live log${RESET}"
echo -e "    ${CY}systemctl --user status vsn_player${RESET}   ${DIM}# service status${RESET}"
echo -e "    ${CY}systemctl --user restart vsn_player${RESET}  ${DIM}# restart player${RESET}"
echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${DIM}              Impact LED Signs  ·  impactledsigns.com${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo
