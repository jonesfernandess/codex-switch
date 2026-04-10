#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Codex Switch installer
# ─────────────────────────────────────────────────────────────────────────────

REPO="jonesfernandess/codex-switch"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="codex-switch"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { printf "${CYAN}::${RESET} %s\n" "$1"; }
success() { printf "${GREEN}✔${RESET}  %s\n" "$1"; }
warn()    { printf "${YELLOW}!${RESET}  %s\n" "$1"; }
error()   { printf "${RED}✘${RESET}  %s\n" "$1"; exit 1; }

# ── Preflight checks ────────────────────────────────────────────────────────

check_deps() {
    if ! command -v codex >/dev/null 2>&1; then
        warn "Codex CLI not found. Install it first:"
        printf "    ${DIM}https://github.com/openai/codex${RESET}\n"
        echo ""
    fi

    if ! command -v gum >/dev/null 2>&1; then
        info "Installing gum (interactive UI)..."
        if command -v brew >/dev/null 2>&1; then
            brew install gum
        else
            warn "gum not found. Install it for the best experience:"
            printf "    ${DIM}brew install gum${RESET}\n"
        fi
    fi
}

# ── Install ──────────────────────────────────────────────────────────────────

install() {
    echo ""
    printf "${BOLD}Codex Switch${RESET} — installer\n"
    echo ""

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Download the script
    info "Downloading codex-switch..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://raw.githubusercontent.com/${REPO}/main/codex-switch" -o "${INSTALL_DIR}/${BINARY_NAME}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${INSTALL_DIR}/${BINARY_NAME}" "https://raw.githubusercontent.com/${REPO}/main/codex-switch"
    else
        error "curl or wget is required to install."
    fi

    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    success "Installed to ${INSTALL_DIR}/${BINARY_NAME}"

    # Check PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^${INSTALL_DIR}$"; then
        warn "${INSTALL_DIR} is not in your PATH."
        echo ""
        info "Add it to your shell config:"
        local shell_config="$HOME/.zshrc"
        if [ -n "${BASH_VERSION:-}" ]; then
            shell_config="$HOME/.bashrc"
        fi
        printf "    ${DIM}echo 'export PATH=\"%s:\$PATH\"' >> %s${RESET}\n" "$INSTALL_DIR" "$shell_config"
        printf "    ${DIM}source %s${RESET}\n" "$shell_config"
        echo ""
    fi

    # Install dependencies
    check_deps

    # ── Optional alias ───────────────────────────────────────────────────────
    local shell_rc="$HOME/.zshrc"
    [ -n "${BASH_VERSION:-}" ] && shell_rc="$HOME/.bashrc"

    echo ""
    printf "  ${BOLD}Optional:${RESET} make every ${CYAN}codex${RESET} call auto-switch accounts.\n"
    printf "  This will add the following line to ${DIM}${shell_rc}${RESET}:\n"
    echo ""
    printf "    ${CYAN}alias codex='codex-switch auto'${RESET}\n"
    echo ""
    printf "  ${DIM}Any time you run 'codex', it will automatically use the next${RESET}\n"
    printf "  ${DIM}profile in rotation and retry on quota/rate-limit errors.${RESET}\n"
    echo ""
    printf "  Add this alias? [y/N] "
    read -r answer </dev/tty
    if [ "${answer:-n}" = "y" ] || [ "${answer:-n}" = "Y" ]; then
        if grep -q "alias codex='codex-switch auto'" "$shell_rc" 2>/dev/null; then
            warn "Alias already present in ${shell_rc}"
        else
            printf '\n# codex-switch: auto-switch accounts on every codex call\nalias codex='"'"'codex-switch auto'"'"'\n' >> "$shell_rc"
            success "Alias added to ${shell_rc}"
            printf "  ${DIM}Run 'source ${shell_rc}' or open a new terminal to activate.${RESET}\n"
        fi
    else
        info "Skipped. You can always add it manually:"
        printf "    ${DIM}echo \"alias codex='codex-switch auto'\" >> %s${RESET}\n" "$shell_rc"
    fi

    echo ""
    success "Installation complete!"
    echo ""
    printf "  Get started:\n"
    printf "    ${CYAN}codex-switch create work${RESET}       ${DIM}# create a profile${RESET}\n"
    printf "    ${CYAN}codex-switch work${RESET}              ${DIM}# launch it${RESET}\n"
    printf "    ${CYAN}codex-switch auto${RESET}              ${DIM}# auto-switch on quota${RESET}\n"
    printf "    ${CYAN}codex-switch${RESET}                   ${DIM}# interactive menu${RESET}\n"
    echo ""
}

# ── Uninstall ────────────────────────────────────────────────────────────────

uninstall() {
    echo ""
    printf "${BOLD}Codex Switch${RESET} — uninstaller\n"
    echo ""

    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        rm -f "${INSTALL_DIR}/${BINARY_NAME}"
        success "Removed ${INSTALL_DIR}/${BINARY_NAME}"
    else
        warn "codex-switch not found at ${INSTALL_DIR}/${BINARY_NAME}"
    fi

    echo ""
    info "Profile directories (~/.codex-*) were not removed."
    info "Remove them manually if needed."
    echo ""
}

# ── Entry point ──────────────────────────────────────────────────────────────

case "${1:-}" in
    uninstall|--uninstall) uninstall ;;
    *)                     install ;;
esac
