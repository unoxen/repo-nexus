#!/bin/sh
# shellcheck shell=sh
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

_script_root=""
if [ -z "${RNEX_REPO_URL:-}" ] && [ -z "${RNEX_TAR_URL:-}" ] && [ "${RNEX_FORCE_TAR:-0}" -ne 1 ]; then
  _cand_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P || true)"
  if [ -n "$_cand_root" ] && [ -f "$_cand_root/rnex" ] && [ -f "$_cand_root/lib/core.sh" ]; then
    _script_root="$_cand_root"
  fi
fi

_need_tar=0
if [ -n "${RNEX_INSTALL_SRC_DIR:-}" ] && [ -d "$RNEX_INSTALL_SRC_DIR" ]; then
  _src_dir="$RNEX_INSTALL_SRC_DIR"
elif [ -d "$REPO_URL" ]; then
  _src_dir="$REPO_URL"
elif [ -n "$_script_root" ]; then
  _src_dir="$_script_root"
elif [ "${RNEX_FORCE_TAR:-0}" -ne 1 ] && command -v git >/dev/null 2>&1; then
  printf '    %bFetching runtime assets via git...%b\n' "$_DIM" "$_NC"
  _clone_url="${REPO_URL%.git}.git"
  if ! git clone -c core.hooksPath=/dev/null --depth 1 --quiet "$_clone_url" "$_src_dir" 2>/dev/null; then
    rm -rf "${_src_dir:?}"
    _need_tar=1
  fi
else
  _need_tar=1
fi

if [ "$_need_tar" -eq 1 ]; then
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

if [ "$_src_dir" != "$INSTALL_DIR" ]; then
  rm -rf "${INSTALL_DIR:?}"
  mkdir -p "$INSTALL_DIR"
  cp "$_src_dir/rnex" "$INSTALL_DIR/rnex"
  [ -f "$_src_dir/package.json" ] && cp "$_src_dir/package.json" "$INSTALL_DIR/package.json"
  for _asset in lib templates plugins skills; do
    if [ -d "$_src_dir/$_asset" ]; then
      cp -R "$_src_dir/$_asset" "$INSTALL_DIR/$_asset"
    fi
  done
  rm -rf "$INSTALL_DIR/plugins"/*/tests 2>/dev/null || true
fi
rm -rf "$_tmp_dir"

chmod +x "$INSTALL_DIR/rnex"
if [ "$BIN_DIR" != "$INSTALL_DIR" ]; then
  ln -sf "$INSTALL_DIR/rnex" "$BIN_DIR/rnex"
fi
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
