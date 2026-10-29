#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# scripts/sync-plugin-versions.sh — Maintainer Plugin Version Synchronization
#
# Synchronizes the 'version:' field in all built-in toolkit plugin manifests
# (toolkit/plugins/*/plugin.yaml) with the current version in package.json.
# Pure POSIX shell compatible (/bin/sh).
# ============================================================================
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_JSON="$REPO_ROOT/package.json"

if [ ! -f "$PKG_JSON" ]; then
  printf 'Error: package.json not found in %s\n' "$REPO_ROOT" >&2
  exit 1
fi

VERSION="$(awk '/"version"[ ]*:/ { sub(/.*"version"[ ]*:[ ]*"/, ""); sub(/".*/, ""); print; exit }' "$PKG_JSON")"
if [ -z "$VERSION" ]; then
  printf 'Error: Unable to extract version from %s\n' "$PKG_JSON" >&2
  exit 1
fi

for manifest in "$REPO_ROOT"/toolkit/plugins/*/plugin.yaml; do
  [ -f "$manifest" ] || continue
  tmp="$manifest.tmp.$$"
  sed "s/^version:[ ].*/version: $VERSION/" "$manifest" > "$tmp" && mv "$tmp" "$manifest"
done

printf '[repo-nexus] Synchronized built-in plugin manifests to v%s\n' "$VERSION"
