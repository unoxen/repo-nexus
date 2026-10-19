#!/bin/sh
set -e
_root="${RNEX_ROOT:-${NEXUS_DIR:-$PWD}}"

if ! command -v merge_rnex_instructions >/dev/null 2>&1; then
  if [ -f "$_root/.rnex/bin/rnex-env.sh" ]; then
    . "$_root/.rnex/bin/rnex-env.sh"
  fi
fi

_gi="$_root/.geminiignore"
if [ ! -f "$_gi" ]; then
  cat > "$_gi" <<GI_EOF
# Gemini CLI file discovery un-ignore for member repos
!repos/*
GI_EOF
  [ "${RNEX_QUIET:-0}" -eq 0 ] && log_ok "Created .geminiignore (enabling Gemini CLI file discovery for member repos)"
elif ! grep -q '!repos/\*' "$_gi" 2>/dev/null; then
  printf '\n# Gemini CLI file discovery un-ignore for member repos\n!repos/*\n' >> "$_gi"
  [ "${RNEX_QUIET:-0}" -eq 0 ] && log_dim "Added !repos/* to .geminiignore"
fi

# Instructions management (always maintained when gemini plugin is enabled)
merge_rnex_instructions "$_root/GEMINI.md"

# Skills management
_sk="$(provider_option_enabled "gemini" "skills" 2>/dev/null && echo "true" || echo "false")"
if [ "$_sk" != "true" ]; then
  clean_provider_user_skills "$_root/.agents/skills"
fi

# Auto-sync hook configuration (SessionStart)
_hooks_file="$_root/.agents/hooks.json"
if provider_auto_sync_enabled "gemini"; then
  if [ ! -f "$_hooks_file" ]; then
    mkdir -p "$_root/.agents"
    cat > "$_hooks_file" <<'EOF'
{
  "rnex-auto-sync": {
    "SessionStart": [
      {
        "type": "command",
        "command": ".rnex/bin/auto-sync.sh"
      }
    ]
  }
}
EOF
  elif ! grep -q '"rnex-auto-sync"' "$_hooks_file" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk '
      /^[ \t]*\{/ && !done {
        print
        print "  \"rnex-auto-sync\": {"
        print "    \"SessionStart\": ["
        print "      {"
        print "        \"type\": \"command\","
        print "        \"command\": \".rnex/bin/auto-sync.sh\""
        print "      }"
        print "    ]"
        print "  },"
        done = 1
        next
      }
      { print }
    ' "$_hooks_file" > "$_tmp" && mv "$_tmp" "$_hooks_file"
  fi
else
  clean_agents_auto_sync_hook "$_hooks_file"
fi

# Clean legacy .gemini/skills if it exists
if [ -d "$_root/.gemini/skills" ]; then
  clean_provider_user_skills "$_root/.gemini/skills"
  rmdir "$_root/.gemini/skills" 2>/dev/null || true
  rmdir "$_root/.gemini" 2>/dev/null || true
fi
