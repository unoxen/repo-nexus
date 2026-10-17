#!/bin/sh
set -e
_hook_dir=""
if [ -n "${RNEX_PLUGIN_DIR:-}" ] && [ -f "$RNEX_PLUGIN_DIR/hooks/after_sync.sh" ]; then
  _hook_dir="$RNEX_PLUGIN_DIR/hooks"
elif [ -n "${RNEX_ROOT:-}" ] && [ -f "$RNEX_ROOT/toolkit/plugins/cursor/hooks/after_sync.sh" ]; then
  _hook_dir="$RNEX_ROOT/toolkit/plugins/cursor/hooks"
elif [ -f "$(dirname "$0")/after_sync.sh" ]; then
  _hook_dir="$(cd "$(dirname "$0")" && pwd -P)"
fi

if [ -n "$_hook_dir" ] && [ -f "$_hook_dir/after_sync.sh" ]; then
  . "$_hook_dir/after_sync.sh"
fi
