#!/bin/sh
# ============================================================================
# Repo Nexus (rnex) — Standalone Zero-Dependency Installer
# https://github.com/unoxen/repo-nexus
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/unoxen/repo-nexus/main/scripts/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/unoxen/repo-nexus/main/scripts/install.sh | sh
# ============================================================================
set -e

if [ -t 1 ]; then
  _G='\033[0;32m' _Y='\033[1;33m' _C='\033[0;36m' _BOLD='\033[1m' _DIM='\033[2m' _NC='\033[0m'
else
  _G='' _Y='' _C='' _BOLD='' _DIM='' _NC=''
fi

REPO_URL="${RNEX_REPO_URL:-https://github.com/unoxen/repo-nexus}"
TAR_URL="${RNEX_TAR_URL:-https://github.com/unoxen/repo-nexus/archive/refs/heads/main.tar.gz}"
INSTALL_DIR="${RNEX_INSTALL_DIR:-$HOME/.local/share/repo-nexus}"
BIN_DIR="${RNEX_BIN_DIR:-$HOME/.local/bin}"

printf '\n%b==>%b Installing Repo Nexus (rnex)...\n' "$_C" "$_NC"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

_tmp_dir="$(mktemp -d)"
trap 'rm -rf "$_tmp_dir"' EXIT INT TERM
_src_dir="$_tmp_dir/src"

if [ "${RNEX_FORCE_TAR:-0}" -ne 1 ] && command -v git >/dev/null 2>&1; then
  printf '    %bFetching runtime assets via git...%b\n' "$_DIM" "$_NC"
  if [ -d "$REPO_URL" ]; then
    git clone --depth 1 --quiet "$REPO_URL" "$_src_dir"
  else
    git clone --depth 1 --quiet "$REPO_URL.git" "$_src_dir"
  fi
else
  printf '    %bDownloading latest archive via curl/wget...%b\n' "$_DIM" "$_NC"
  _tmp_tar="$_tmp_dir/repo.tar.gz"
  if [ -f "$TAR_URL" ]; then
    cp "$TAR_URL" "$_tmp_tar"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TAR_URL" -o "$_tmp_tar"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_tmp_tar" "$TAR_URL"
  else
    printf 'Error: curl, wget, or git is required to install Repo Nexus.\n' >&2
    exit 1
  fi
  mkdir -p "$_src_dir"
  tar -xzf "$_tmp_tar" -C "$_src_dir" --strip-components=1
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp "$_src_dir/rnex" "$INSTALL_DIR/rnex"
[ -f "$_src_dir/package.json" ] && cp "$_src_dir/package.json" "$INSTALL_DIR/package.json"
for _asset in lib templates toolkit; do
  if [ -d "$_src_dir/$_asset" ]; then
    cp -R "$_src_dir/$_asset" "$INSTALL_DIR/$_asset"
  fi
done
rm -rf "$_tmp_dir"

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
