#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# toolkit/plugins/karpathy-llm/hooks/_common.sh — Shared Karpathy Wiki Hook Bootstrap
# ============================================================================

_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"
NEXUS_DIR="$_root"
RNEX_ROOT="$_root"
WORKSPACE_YAML="${WORKSPACE_YAML:-$_root/rnex.yaml}"
WORKSPACE_LOCAL_YAML="${WORKSPACE_LOCAL_YAML:-$_root/.local.rnex.yaml}"
export NEXUS_DIR RNEX_ROOT WORKSPACE_YAML WORKSPACE_LOCAL_YAML

if ! command -v yaml_plugin_get >/dev/null 2>&1 || ! command -v plugin_primary_source_dir >/dev/null 2>&1; then
  _kl_hook_dir="$(dirname "${_kl_common:-$0}")"
  for _kl_lib in \
    "${RNEX_LIB_DIR:-}" \
    "$_kl_hook_dir/../../../../lib" \
    "$_kl_hook_dir/../../../lib" \
    "$_root/lib"; do
    if [ -n "$_kl_lib" ] && [ -f "$_kl_lib/yaml.sh" ]; then
      RNEX_LIB_DIR="$(cd "$_kl_lib" 2>/dev/null && pwd -P)"
      export RNEX_LIB_DIR
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/core.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/yaml.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/plugins.sh" 2>/dev/null || true
      # shellcheck source=/dev/null
      . "$RNEX_LIB_DIR/sdk.sh" 2>/dev/null || true
      break
    fi
  done
  if ! command -v provider_option_get >/dev/null 2>&1 && [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    # shellcheck source=/dev/null
    . "$_root/.rnex/bin/rnex-env.sh" 2>/dev/null || true
  fi
fi

get_cfg() {
  _gc_key="$1"; _gc_def="${2:-}"
  _gc_val=""
  if command -v yaml_plugin_get >/dev/null 2>&1; then
    _gc_val="$(yaml_plugin_get "karpathy-llm" "$_gc_key" 2>/dev/null || true)"
  elif command -v provider_option_get >/dev/null 2>&1; then
    _gc_val="$(provider_option_get "karpathy-llm" "$_gc_key" 2>/dev/null || true)"
  fi
  [ -n "$_gc_val" ] && printf '%s' "$_gc_val" || printf '%s' "$_gc_def"
}

_wiki="$(get_cfg "wiki_dir" "wiki")"
_wiki="$(printf '%s' "$_wiki" | sed -e 's#^/##' -e 's#/$##')"
_wiki_path="$_root/$_wiki"

_raw="$(get_cfg "raw_dir" "./docs")"
_raw="$(printf '%s' "$_raw" | sed -e 's#^\./##' -e 's#^/##' -e 's#/$##')"
if command -v plugin_primary_source_dir >/dev/null 2>&1; then
  _psd="$(plugin_primary_source_dir "karpathy-llm" 2>/dev/null || true)"
  [ -n "$_psd" ] && _raw="$_psd"
fi
[ -n "$_raw" ] || _raw="docs"
_raw_path="$_root/$_raw"
