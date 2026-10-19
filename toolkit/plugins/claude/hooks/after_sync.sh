#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

# Instructions management (always maintained when claude plugin is enabled)
merge_rnex_instructions "$_root/CLAUDE.md"

# Skills management
_sk="$(provider_option_enabled "claude" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  clean_provider_user_skills "$_root/.claude/skills"
fi

# Auto-sync hook configuration (SessionStart)
_settings="$_root/.claude/settings.json"
if provider_auto_sync_enabled "claude"; then
  mkdir -p "$_root/.claude"
  if [ ! -f "$_settings" ]; then
    cat > "$_settings" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "command": ".rnex/bin/auto-sync.sh"
      }
    ]
  }
}
EOF
  elif ! grep -q "auto-sync.sh" "$_settings" 2>/dev/null; then
    if grep -q '"SessionStart"' "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk '
        /"SessionStart"[ ]*:[ ]*\[/ {
          print
          print "      { \"command\": \".rnex/bin/auto-sync.sh\" },"
          next
        }
        { print }
      ' "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
    elif grep -q '"hooks"' "$_settings" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk '
        /"hooks"[ ]*:[ ]*\{/ {
          print
          print "    \"SessionStart\": [ { \"command\": \".rnex/bin/auto-sync.sh\" } ],"
          next
        }
        { print }
      ' "$_settings" > "$_tmp" && mv "$_tmp" "$_settings"
    fi
  fi
else
  clean_claude_auto_sync_hook "$_settings"
  rmdir "$_root/.claude" 2>/dev/null || true
fi
