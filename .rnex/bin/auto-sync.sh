#!/bin/sh
set -e
_ws="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P)"
[ -f "$_ws/rnex.yaml" ] || exit 0

_stamp="$_ws/.rnex/.sync_stamp"
_cur_sum="$(cd "$_ws" 2>/dev/null && cksum rnex.yaml .local.rnex.yaml 2>/dev/null | cksum | awk '{print $1, $2}')"
_saved_sum=""
[ -f "$_stamp" ] && _saved_sum="$(cat "$_stamp" 2>/dev/null)"

if [ ! -f "$_stamp" ] || [ "$_cur_sum" != "$_saved_sum" ]; then
  if [ -x "$_ws/rnex" ]; then
    "$_ws/rnex" sync -y --quiet
  elif command -v rnex >/dev/null 2>&1; then
    (cd "$_ws" && rnex sync -y --quiet)
  fi
fi
