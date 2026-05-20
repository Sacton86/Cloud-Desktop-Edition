#!/usr/bin/env bash
# updater.sh — Impact Cloud+ VSN Player  ·  Self-updater (curl only, no git)
#
# Usage:  sudo bash updater.sh
#
# Set GITHUB_REPO to your GitHub "owner/repo" before deploying, e.g.:
#   GITHUB_REPO="impactledsigns/vsn-player"
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────
GITHUB_REPO="${GITHUB_REPO:-Sacton86/Cloud-Desktop-Edition}"
INSTALL_DIR="${INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SERVICE_NAME="vsn_player"

# ── ANSI colours ─────────────────────────────────────────────────
RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
CY="\033[36m"; CYB="\033[1;36m"; YL="\033[33m"; GR="\033[32m"; RD="\033[31m"; WH="\033[97m"

hr()     { echo -e "${DIM}${CY}  ─────────────────────────────────────────────────────────────${RESET}"; }
section(){ echo; echo -e "${CYB}  ◈  $1${RESET}"; hr; }
ok()     { echo -e "${GR}  ✔  ${RESET}$1"; }
info()   { echo -e "${CY}  ·  ${RESET}$1"; }
warn()   { echo -e "${YL}  ⚠  ${RESET}$1"; }
err()    { echo -e "${RD}  ✘  ${RESET}$1" >&2; }

# ── Banner ───────────────────────────────────────────────────────
echo
echo -e "${CYB}"
echo '   ██╗███╗   ███╗██████╗  █████╗  ██████╗████████╗'
echo '   ██║████╗ ████║██╔══██╗██╔══██╗██╔════╝╚══██╔══╝'
echo '   ██║██╔████╔██║██████╔╝███████║██║        ██║   '
echo '   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║        ██║   '
echo '   ██║██║ ╚═╝ ██║██║     ██║  ██║╚██████╗   ██║   '
echo '   ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝   ╚═╝   '
echo -e "${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CY}     Cloud+ Player  ·  Software Updater  ·  Impact LED Signs${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"

# ── Root check ───────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "Run as root:  sudo bash updater.sh"
    exit 1
fi

SERVICE_USER="${SUDO_USER:-$USER}"
XDG_RUNTIME_DIR="/run/user/$(id -u "$SERVICE_USER")"
export XDG_RUNTIME_DIR

run_as_user() {
    sudo -u "$SERVICE_USER" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        systemctl --user "$@"
}

# ── Step 1: Check current version ────────────────────────────────
section "[1/4]  Checking Installed Version"

CURRENT_VERSION="unknown"
if [[ -f "$INSTALL_DIR/version.txt" ]]; then
    CURRENT_VERSION=$(cat "$INSTALL_DIR/version.txt" | tr -d '[:space:]')
elif [[ -f "$INSTALL_DIR/player.py" ]]; then
    CURRENT_VERSION=$(grep -m1 '^VERSION\s*=' "$INSTALL_DIR/player.py" \
                        | grep -oP '"\K[^"]+' || echo "unknown")
fi
info "Installed version : ${WH}${CURRENT_VERSION}${RESET}"
info "Install directory : ${WH}${INSTALL_DIR}${RESET}"
info "GitHub repo       : ${WH}${GITHUB_REPO}${RESET}"

# ── Step 2: Fetch latest release tag from GitHub API ─────────────
section "[2/4]  Checking for Updates"

API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
info "Querying GitHub API…"

RESPONSE=$(curl -sf --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "$API_URL" 2>/dev/null || true)

if [[ -z "$RESPONSE" ]]; then
    err "Could not reach GitHub API. Check your internet connection."
    err "URL: ${API_URL}"
    exit 1
fi

LATEST_TAG=$(printf '%s' "$RESPONSE" | grep -oP '"tag_name":\s*"\K[^"]+' || true)
TARBALL_URL=$(printf '%s' "$RESPONSE" | grep -oP '"tarball_url":\s*"\K[^"]+' || true)

if [[ -z "$LATEST_TAG" ]]; then
    err "No releases found for ${GITHUB_REPO}. Have you published a GitHub Release yet?"
    exit 1
fi

info "Latest release    : ${WH}${LATEST_TAG}${RESET}"

# Normalise: strip leading 'v' for comparison
norm() { printf '%s' "${1#v}"; }
CURR_NORM=$(norm "$CURRENT_VERSION")
LATEST_NORM=$(norm "$LATEST_TAG")

if [[ "$CURR_NORM" == "$LATEST_NORM" ]]; then
    ok "Already up to date  (${CURRENT_VERSION})."
    echo
    echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GR}${BOLD}     ✔  No update needed.${RESET}"
    echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
    echo
    exit 0
fi

warn "Update available:  ${CURRENT_VERSION}  →  ${LATEST_TAG}"

# ── Step 3: Download and extract release tarball ─────────────────
section "[3/4]  Downloading ${LATEST_TAG}"

TMP_DIR=$(mktemp -d)
TARBALL_PATH="$TMP_DIR/release.tar.gz"

# Prefer the tarball_url from the API response; fall back to the predictable GitHub URL
DOWNLOAD_URL="${TARBALL_URL:-https://github.com/${GITHUB_REPO}/archive/refs/tags/${LATEST_TAG}.tar.gz}"
info "Downloading from  : ${WH}${DOWNLOAD_URL}${RESET}"

curl -sfL --max-time 120 -o "$TARBALL_PATH" "$DOWNLOAD_URL"
ok "Download complete."

info "Extracting archive…"
tar -xz -C "$TMP_DIR" -f "$TARBALL_PATH"

# GitHub tarballs extract to "owner-repo-<sha>/" — find it
EXTRACTED_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
    err "Could not find extracted directory inside tarball."
    rm -rf "$TMP_DIR"
    exit 1
fi
ok "Extracted to       : ${DIM}${EXTRACTED_DIR}${RESET}"

# ── Step 4: Install new files & restart ──────────────────────────
section "[4/4]  Installing Update"

# Files to copy (credentials config and downloads are excluded — never overwrite)
FILES_TO_COPY=(
    player.py
    install.sh
    updater.sh
    requirements.txt
    vsn_player.service
    README.md
    .gitignore
    player_config.example.json
)

for f in "${FILES_TO_COPY[@]}"; do
    src="$EXTRACTED_DIR/$f"
    if [[ -f "$src" ]]; then
        cp "$src" "$INSTALL_DIR/$f"
        ok "Updated  $f"
    else
        warn "Not in release:  $f  (skipped)"
    fi
done

# Copy fonts directory if present
if [[ -d "$EXTRACTED_DIR/fonts" ]]; then
    rsync -a --delete "$EXTRACTED_DIR/fonts/" "$INSTALL_DIR/fonts/" 2>/dev/null \
        || cp -r "$EXTRACTED_DIR/fonts/." "$INSTALL_DIR/fonts/"
    ok "Updated  fonts/"
fi

# Install updated Python dependencies
info "Updating Python packages…"
pip3 install --break-system-packages -q -r "$INSTALL_DIR/requirements.txt"
ok "Python packages up to date."

# Reload service definition in case vsn_player.service changed
run_as_user daemon-reload

# Restart the player service
info "Restarting ${SERVICE_NAME} service…"
run_as_user restart "$SERVICE_NAME" && ok "Service restarted." \
    || warn "Service restart deferred — it will pick up on next boot."

rm -rf "$TMP_DIR"

# Record installed version so player.py and future updater runs can read it
printf '%s' "$LATEST_TAG" > "$INSTALL_DIR/version.txt"
ok "Recorded version   : ${LATEST_TAG}"

# ── Summary ──────────────────────────────────────────────────────
echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GR}${BOLD}     ✔  Updated  ${CURRENT_VERSION}  →  ${LATEST_TAG}${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo
echo -e "  ${DIM}To verify:${RESET}"
echo -e "    ${CY}journalctl --user -u vsn_player -f${RESET}    ${DIM}# live log${RESET}"
echo -e "    ${CY}systemctl --user status vsn_player${RESET}    ${DIM}# service status${RESET}"
echo
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo -e "${DIM}              Impact LED Signs  ·  impactledsigns.com${RESET}"
echo -e "${DIM}${CY}  ══════════════════════════════════════════════════════════════${RESET}"
echo
