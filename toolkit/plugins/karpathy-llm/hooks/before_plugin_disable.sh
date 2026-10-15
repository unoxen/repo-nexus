#!/bin/sh
set -e

[ -z "$RNEX_ROOT" ] && { echo "Error: RNEX_ROOT not set"; exit 1; }

# Helper fallback in case not already loaded in environment
if ! command -v rnex_unregister_user_skill >/dev/null 2>&1; then
  if [ -f "$RNEX_ROOT/.rnex/bin/rnex-env.sh" ]; then
    . "$RNEX_ROOT/.rnex/bin/rnex-env.sh"
  fi
fi

if command -v rnex_unregister_user_skill >/dev/null 2>&1; then
  rnex_unregister_user_skill "wiki-ingest"
  rnex_unregister_user_skill "wiki-lint"
else
  for _pdir in $RNEX_PROVIDER_SKILL_DIRS; do
    rm -f "$RNEX_ROOT/$_pdir/rnex-wiki-ingest.md"
    rm -f "$RNEX_ROOT/$_pdir/rnex-wiki-lint.md"
  done
fi
