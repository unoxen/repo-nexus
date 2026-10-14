#!/bin/sh
# ============================================================================
# Repo Nexus (rnex) — Standalone Zero-Dependency Installer
# https://github.com/nu-nenoi/repo-nexus
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nu-nenoi/repo-nexus/main/scripts/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/nu-nenoi/repo-nexus/main/scripts/install.sh | sh
# ============================================================================
set -e

if [ -t 1 ]; then
  _G='\033[0;32m' _Y='\033[1;33m' _C='\033[0;36m' _BOLD='\033[1m' _DIM='\033[2m' _NC='\033[0m'
else
  _G='' _Y='' _C='' _BOLD='' _DIM='' _NC=''
fi

REPO_URL="https://github.com/nu-nenoi/repo-nexus"
TAR_URL="https://github.com/nu-nenoi/repo-nexus/archive/refs/heads/main.tar.gz"
INSTALL_DIR="${RNEX_INSTALL_DIR:-$HOME/.local/share/repo-nexus}"
BIN_DIR="${RNEX_BIN_DIR:-$HOME/.local/bin}"

printf '\n%b==>%b Installing Repo Nexus (rnex)...\n' "$_C" "$_NC"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

if command -v git >/dev/null 2>&1; then
  if [ -d "$INSTALL_DIR/.git" ]; then
    printf '    %bUpdating existing installation in %s%b\n' "$_DIM" "$INSTALL_DIR" "$_NC"
    git -C "$INSTALL_DIR" pull --quiet --ff-only 2>/dev/null || true
  else
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 --quiet "$REPO_URL.git" "$INSTALL_DIR"
  fi
else
  printf '    %bDownloading latest archive via curl/wget...%b\n' "$_DIM" "$_NC"
  _tmp_tar="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TAR_URL" -o "$_tmp_tar"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_tmp_tar" "$TAR_URL"
  else
    printf 'Error: curl, wget, or git is required to install Repo Nexus.\n' >&2
    exit 1
  fi
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$_tmp_tar" -C "$INSTALL_DIR" --strip-components=1
  rm -f "$_tmp_tar"
fi

chmod +x "$INSTALL_DIR/rnex"
ln -sf "$INSTALL_DIR/rnex" "$BIN_DIR/rnex"
ln -sf "$INSTALL_DIR/rnex" "$BIN_DIR/repo-nexus"

printf '%b[✓]%b Successfully installed %brnex%b and %brepo-nexus%b into %b%s%b\n\n' \
  "$_G" "$_NC" "$_BOLD" "$_NC" "$_BOLD" "$_NC" "$_BOLD" "$BIN_DIR" "$_NC"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    printf '%bNote:%b %s is not in your current PATH.\n' "$_Y" "$_NC" "$BIN_DIR"
    printf 'Add it to your shell profile (~/.zshrc or ~/.bashrc):\n'
    printf "  export PATH=\"%s:\$PATH\"\n\n" "$BIN_DIR"
    ;;
esac
