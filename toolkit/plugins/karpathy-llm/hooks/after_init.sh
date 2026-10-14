#!/bin/sh
set -e
_hook_dir="$(cd "$(dirname "$0")" && pwd -P)"
if [ -f "$_hook_dir/after_sync.sh" ]; then
  . "$_hook_dir/after_sync.sh"
fi
