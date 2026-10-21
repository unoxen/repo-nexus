#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/yaml.sh — YAML Parser / Manipulator (for rnex.yaml & .local.rnex.yaml)
# ============================================================================

_yaml_list_plugins_from_file() {
  _f="$1"
  [ -f "$_f" ] || return 0
  awk '
    /^[ \t]*plugins:[ \t]*(#.*)?$/ { in_plugins=1; plugin_indent=-1; next }
    in_plugins && /^[^ \t#]/ { in_plugins=0 }
    !in_plugins { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_plugins && (plugin_indent == -1) && (indent > 0) {
      plugin_indent = indent
    }

    in_plugins && (indent == plugin_indent) {
      if (trimmed ~ /^["\047]?[a-zA-Z0-9_.-]+["\047]?:/) {
        line = trimmed
        sub(/:.*/, "", line)
        gsub(/^["\047]|["\047]$/, "", line)
        gsub(/[[:space:]]/, "", line)
        if (length(line) > 0) print line
      } else if (trimmed ~ /^-[ \t]+["\047]?[a-zA-Z0-9_.-]+/) {
        line = trimmed
        sub(/^-[ \t]+/, "", line)
        sub(/[ \t]*#.*/, "", line)
        sub(/:.*/, "", line)
        gsub(/^["\047]|["\047]$/, "", line)
        gsub(/[[:space:]]/, "", line)
        if (length(line) > 0) print line
      }
    }
  ' "$_f"
}

yaml_list_plugins() {
  _wy="${WORKSPACE_YAML:-}"
  [ -z "$_wy" ] && _wy="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$_wly" ] && _wly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  {
    _yaml_list_plugins_from_file "$_wy"
    _yaml_list_plugins_from_file "$_wly"
  } | awk '!seen[$0]++'
}

_yaml_plugin_get_from_file() {
  _f="$1"; _pname="$2"; _key="$3"
  [ -f "$_f" ] || return 0
  awk -v plugin="$_pname" -v key="$_key" '
    /^[ \t]*plugins:[ \t]*(#.*)?$/ { in_plugins=1; in_target=0; plugin_indent=-1; next }
    in_plugins && /^[^ \t#]/ { in_plugins=0; in_target=0 }
    !in_plugins { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_target && (indent <= plugin_indent) {
      in_target=0
    }

    !in_target {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_target=1
        plugin_indent=indent
        next
      }
    }

    in_target && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == key && trimmed ~ /:[ \t]*/) {
        val = trimmed
        sub(/^[^:]*:[ \t]*/, "", val)
        if (val ~ /^"[^"]*"/) {
          match(val, /^"[^"]*"/)
          val = substr(val, 2, RLENGTH - 2)
        } else if (val ~ /^\047[^\047]*\047/) {
          match(val, /^\047[^\047]*\047/)
          val = substr(val, 2, RLENGTH - 2)
        } else {
          sub(/[ \t]*#.*$/, "", val)
          sub(/[ \t]+$/, "", val)
        }
        print val
        exit
      }
    }
  ' "$_f"
}

yaml_plugin_get() {
  _pname="$1"; _key="$2"
  _wy="${WORKSPACE_YAML:-}"
  [ -z "$_wy" ] && _wy="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$_wly" ] && _wly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  _val="$(_yaml_plugin_get_from_file "$_wly" "$_pname" "$_key")"
  if [ -n "$_val" ]; then
    printf '%s' "$_val"
    return 0
  fi
  _yaml_plugin_get_from_file "$_wy" "$_pname" "$_key"
}

# Extract list items under plugins.<plugin>.<key> from a single config file.
# Supports block sequences ("- item", nested deeper or at the key's indent),
# inline flow sequences ("[a, \"b\"]") and a plain scalar (single item).
# Surrounding quotes and inline comments are stripped. One item per line.
_yaml_plugin_list_from_file() {
  _ypl_f="$1"; _ypl_plugin="$2"; _ypl_key="$3"
  [ -f "$_ypl_f" ] || return 0
  awk -v plugin="$_ypl_plugin" -v key="$_ypl_key" '
    function unquote(v) {
      sub(/^[ \t]+/, "", v)
      if (v ~ /^"/) {
        v = substr(v, 2); sub(/".*$/, "", v)
      } else if (v ~ /^\047/) {
        v = substr(v, 2); sub(/\047.*$/, "", v)
      } else {
        sub(/[ \t]+#.*$/, "", v)
        sub(/[ \t]+$/, "", v)
      }
      return v
    }
    /^[ \t]*plugins:[ \t]*(#.*)?$/ { in_plugins=1; in_target=0; in_list=0; plugin_indent=-1; next }
    in_plugins && /^[^ \t#]/ {
      if (in_list) exit
      in_plugins=0; in_target=0
      next
    }
    !in_plugins { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_list {
      if (indent > key_indent || (indent == key_indent && trimmed ~ /^-([ \t]|$)/)) {
        if (trimmed ~ /^-([ \t]|$)/) {
          item = unquote(substr(trimmed, 2))
          if (length(item) > 0) print item
        }
        next
      }
      exit
    }

    in_target && (indent <= plugin_indent) { in_target=0 }

    !in_target {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_target=1
        plugin_indent=indent
      }
      next
    }

    in_target && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k != key) next
      val = trimmed
      sub(/^[^:]*:[ \t]*/, "", val)
      if (val ~ /^(#.*)?$/) {
        in_list=1
        key_indent=indent
        next
      }
      if (val ~ /^\[/) {
        sub(/^\[/, "", val)
        sub(/\][ \t]*(#.*)?$/, "", val)
        n = split(val, parts, ",")
        for (i = 1; i <= n; i++) {
          item = unquote(parts[i])
          if (length(item) > 0) print item
        }
        exit
      }
      item = unquote(val)
      if (length(item) > 0) print item
      exit
    }
  ' "$_ypl_f"
}

# Get a list-valued plugin setting as newline-separated items.
# Precedence: .local.rnex.yaml (if non-empty) overrides the entire list in rnex.yaml.
# For karpathy-llm "sources": falls back to the legacy scalar raw_dir (with a
# deprecation warning on stderr), then to the defaults "docs" and "repos/**/README.md".
get_plugin_config_list() {
  _gpl_plugin="$1"; _gpl_key="$2"
  _gpl_wy="${WORKSPACE_YAML:-}"
  [ -z "$_gpl_wy" ] && _gpl_wy="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _gpl_wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$_gpl_wly" ] && _gpl_wly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"

  _gpl_items="$(_yaml_plugin_list_from_file "$_gpl_wly" "$_gpl_plugin" "$_gpl_key")"
  [ -z "$_gpl_items" ] && _gpl_items="$(_yaml_plugin_list_from_file "$_gpl_wy" "$_gpl_plugin" "$_gpl_key")"
  if [ -n "$_gpl_items" ]; then
    printf '%s\n' "$_gpl_items"
    return 0
  fi

  case "$_gpl_plugin:$_gpl_key" in
    karpathy-llm:sources)
      _gpl_raw="$(plugin_legacy_raw_dir "$_gpl_plugin")"
      if [ -n "$_gpl_raw" ]; then
        log_warn "plugins.$_gpl_plugin.raw_dir is deprecated; replace it with a 'sources' list in ${RNEX_CONFIG_FILE:-rnex.yaml} (or ${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}) and run 'rnex sync'." >&2
        printf '%s\n' "$_gpl_raw"
      else
        printf '%s\n' "docs" "repos/**/README.md"
      fi
      ;;
  esac
}

# Print the legacy scalar raw_dir value when it is still in effect, i.e. when no
# 'sources' list is configured in either config file. Prints nothing otherwise.
plugin_legacy_raw_dir() {
  _plr_plugin="$1"
  _plr_wy="${WORKSPACE_YAML:-}"
  [ -z "$_plr_wy" ] && _plr_wy="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _plr_wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$_plr_wly" ] && _plr_wly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  [ -n "$(_yaml_plugin_list_from_file "$_plr_wly" "$_plr_plugin" "sources")" ] && return 0
  [ -n "$(_yaml_plugin_list_from_file "$_plr_wy" "$_plr_plugin" "sources")" ] && return 0
  yaml_plugin_get "$_plr_plugin" "raw_dir" 2>/dev/null || true
}

# Emit a plugin's config_defaults block from plugin.yaml, re-indented for insertion
# under plugins.<name> in rnex.yaml: keys at 4 spaces, list items at 6 spaces.
plugin_config_default_lines() {
  _pcd_file="$1"
  [ -f "$_pcd_file" ] || return 0
  awk '
    /^config_defaults:[ ]*$/ || /^config_defaults:[ ]*#/ { in_c=1; next }
    in_c && /^[^ #]/ { exit }
    in_c && /^[ ]*[a-zA-Z0-9_.-]+:[ ]*/ {
      line = $0
      sub(/^[ ]*/, "    ", line)
      print line
      next
    }
    in_c && /^[ ]+-([ ]|$)/ {
      line = $0
      sub(/^[ ]*/, "      ", line)
      print line
    }
  ' "$_pcd_file"
}

yaml_has_plugin() {
  yaml_list_plugins | grep -qx "$1" 2>/dev/null
}

yaml_plugin_enabled() {
  _plugin="$1"
  yaml_has_plugin "$_plugin" || return 1
  _val="$(yaml_plugin_get "$_plugin" "enabled")"
  _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
  case "$_val" in
    false|no|0|disabled|off) return 1 ;;
    *) return 0 ;;
  esac
}

provider_plugin_enabled() {
  _p="$1"
  if yaml_plugin_enabled "$_p"; then
    return 0
  fi
  return 1
}

provider_option_enabled() {
  _p="$1"
  _opt="$2"
  provider_plugin_enabled "$_p" || return 1
  _val="$(yaml_plugin_get "$_p" "$_opt")"
  _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
  case "$_val" in
    false|no|0|disabled|off) return 1 ;;
    *) return 0 ;;
  esac
}

provider_auto_sync_enabled() {
  _p="$1"
  provider_plugin_enabled "$_p" || return 1
  _val="$(yaml_plugin_get "$_p" "auto_sync_on")"
  [ -z "$_val" ] && _val="$(yaml_plugin_get "$_p" "autoSyncOn")"
  [ -z "$_val" ] && _val="SessionStart"
  _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
  case "$_val" in
    false|no|0|disabled|off|none) return 1 ;;
    *) return 0 ;;
  esac
}

copilot_plugin_enabled() { provider_plugin_enabled "copilot"; }
copilot_instructions_enabled() { provider_plugin_enabled "copilot"; }
copilot_skills_enabled() { provider_option_enabled "copilot" "skills"; }

claude_plugin_enabled() { provider_plugin_enabled "claude"; }
claude_instructions_enabled() { provider_plugin_enabled "claude"; }
claude_skills_enabled() { provider_option_enabled "claude" "skills"; }
claude_auto_sync_enabled() { provider_auto_sync_enabled "claude"; }

gemini_plugin_enabled() { provider_plugin_enabled "gemini"; }
gemini_instructions_enabled() { provider_plugin_enabled "gemini"; }
gemini_skills_enabled() { provider_option_enabled "gemini" "skills"; }
gemini_auto_sync_enabled() { provider_auto_sync_enabled "gemini"; }

cursor_plugin_enabled() { provider_plugin_enabled "cursor"; }
cursor_instructions_enabled() { provider_plugin_enabled "cursor"; }
cursor_skills_enabled() { provider_option_enabled "cursor" "skills"; }

windsurf_plugin_enabled() { provider_plugin_enabled "windsurf"; }
windsurf_instructions_enabled() { provider_plugin_enabled "windsurf"; }
windsurf_skills_enabled() { provider_option_enabled "windsurf" "skills"; }

has_active_provider_instructions() {
  _dir="${1:-${NEXUS_DIR:-$PWD}}"
  _saved_ws_yaml="${WORKSPACE_YAML:-}"
  _saved_local_yaml="${WORKSPACE_LOCAL_YAML:-}"
  if [ -n "$1" ] && [ -d "$1" ]; then
    WORKSPACE_YAML="$1/rnex.yaml"
    WORKSPACE_LOCAL_YAML="$1/.local.rnex.yaml"
  fi
  _res=1
  if copilot_instructions_enabled || \
     claude_instructions_enabled || \
     gemini_instructions_enabled || \
     cursor_instructions_enabled || \
     windsurf_instructions_enabled; then
    _res=0
  fi
  if [ -n "$1" ] && [ -d "$1" ]; then
    WORKSPACE_YAML="$_saved_ws_yaml"
    WORKSPACE_LOCAL_YAML="$_saved_local_yaml"
  fi
  return $_res
}

_yaml_plugin_set_in_file() {
  _file="$1"; _plugin="$2"; _field="$3"; _value="$4"
  if [ ! -f "$_file" ]; then
    mkdir -p "$(dirname "$_file")"
    printf 'plugins:\n' > "$_file"
  elif ! grep -q '^plugins:' "$_file" 2>/dev/null; then
    printf '\nplugins:\n' >> "$_file"
  fi

  if ! awk -v plugin="$_plugin" '
    /^plugins:[ ]*$/ || /^plugins:[ ]*#/ { in_p=1; next }
    in_p && /^[^ #]/ { in_p=0 }
    in_p && match($0, "^  " plugin ":[ ]*(#.*)?$") { found=1; exit }
    END { exit !found }
  ' "$_file" 2>/dev/null; then
    if grep -qE "^  $_plugin:[ ]*(\{\}|\[\])?$" "$_file" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v plugin="$_plugin" -v field="$_field" -v value="$_value" '
        match($0, "^  " plugin ":[ ]*(\\{\\}|\\[\\])?$") {
          printf "  %s:\n    %s: %s\n", plugin, field, value
          next
        }
        { print }
      ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
      return 0
    fi
    _tmp="$(mktemp)"
    awk -v plugin="$_plugin" -v field="$_field" -v value="$_value" '
      /^plugins:[ ]*$/ || /^plugins:[ ]*#/ {
        print
        printf "  %s:\n    %s: %s\n", plugin, field, value
        added=1
        next
      }
      { print }
      END {
        if (!added) {
          printf "plugins:\n  %s:\n    %s: %s\n", plugin, field, value
        }
      }
    ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
    return 0
  fi

  _tmp="$(mktemp)"
  awk -v plugin="$_plugin" -v field="$_field" -v value="$_value" '
    /^plugins:/ { in_plugins=1; print; next }
    in_plugins && /^[^ #]/ {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
        field_set=1
      }
      in_plugins=0; in_target=0
    }
    in_plugins && match($0, "^  " plugin ":[ ]*(#.*)?$") {
      in_target=1; print; next
    }
    in_target && /^  [^ #]/ {
      if (!field_set) {
        printf "    %s: %s\n", field, value
        field_set=1
      }
      in_target=0
    }
    in_target && match($0, "^    " field ":") {
      printf "    %s: %s\n", field, value
      field_set=1
      next
    }
    { print }
    END {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
      }
    }
  ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}

yaml_plugin_set() {
  _plugin="$1"; _field="$2"; _value="$3"
  _yaml_plugin_set_in_file "$WORKSPACE_YAML" "$_plugin" "$_field" "$_value"
}

yaml_plugin_set_local() {
  _plugin="$1"; _field="$2"; _value="$3"
  if [ ! -f "$WORKSPACE_LOCAL_YAML" ]; then
    cat <<'EOF' > "$WORKSPACE_LOCAL_YAML"
# ==============================================================================
# .local.rnex.yaml — Repo Nexus Local Configuration (Machine-Specific)
# ==============================================================================
# This file is gitignored. Use it to specify local repository paths, overrides,
# and enable/disable states for this workstation.

plugins:
EOF
  fi
  _yaml_plugin_set_in_file "$WORKSPACE_LOCAL_YAML" "$_plugin" "$_field" "$_value"
}

yaml_enable_plugin() {
  _name="$1"
  _target_file="${2:-$WORKSPACE_YAML}"
  if [ ! -f "$_target_file" ]; then
    printf 'plugins:\n' > "$_target_file"
  elif ! grep -q '^plugins:' "$_target_file" 2>/dev/null; then
    printf '\nplugins:\n' >> "$_target_file"
  fi
  if ! _yaml_list_plugins_from_file "$_target_file" | grep -qx "$_name" 2>/dev/null; then
    _pdir="$(find_plugin_dir "$_name" 2>/dev/null || true)"
    _cfg_lines=""
    if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
      _cfg_lines="$(plugin_config_default_lines "$_pdir/plugin.yaml")"
    fi

    _tmp="$(mktemp)"
    if [ -n "$_cfg_lines" ]; then
      _cfg_tmp="$(mktemp)"
      printf '%s\n' "$_cfg_lines" > "$_cfg_tmp"
      awk -v name="$_name" -v cfg_file="$_cfg_tmp" '
        /^plugins:[ ]*$/ || /^plugins:[ ]*#/ {
          print
          printf "  %s:\n", name
          while ((getline line < cfg_file) > 0) print line
          close(cfg_file)
          added=1
          next
        }
        { print }
        END {
          if (!added) {
            printf "plugins:\n  %s:\n", name
            while ((getline line < cfg_file) > 0) print line
            close(cfg_file)
          }
        }
      ' "$_target_file" > "$_tmp"
      rm -f "$_cfg_tmp"
      mv "$_tmp" "$_target_file"
    else
      awk -v name="$_name" '
        /^plugins:[ ]*$/ || /^plugins:[ ]*#/ {
          print
          printf "  %s: {}\n", name
          added=1
          next
        }
        { print }
        END {
          if (!added) {
            printf "plugins:\n  %s: {}\n", name
          }
        }
      ' "$_target_file" > "$_tmp" && mv "$_tmp" "$_target_file"
    fi
  else
    if [ -f "$_target_file" ]; then
      _yaml_plugin_set_in_file "$_target_file" "$_name" "enabled" "true"
    fi
  fi
}

_yaml_disable_plugin_in_file() {
  _file="$1"; _name="$2"
  [ -f "$_file" ] || return 0
  _tmp="$(mktemp)"
  awk -v name="$_name" '
    /^plugins:/ { in_plugins=1; print; next }
    in_plugins && /^[^ #]/ { in_plugins=0 }
    in_plugins && match($0, "^  " name ":") { skip=1; next }
    in_plugins && skip && /^  [^ #]/ { skip=0 }
    skip && /^    / { next }
    { print }
  ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}

yaml_disable_plugin() {
  _name="$1"
  _yaml_disable_plugin_in_file "$WORKSPACE_YAML" "$_name"
  _yaml_disable_plugin_in_file "$WORKSPACE_LOCAL_YAML" "$_name"
}

# Parse list of repos from a single config file
_yaml_list_repos_from_file() {
  _f="$1"
  [ -f "$_f" ] || return 0
  awk '
    /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
    r && /^[^ #]/ { r=0 }
    r && /^  [a-zA-Z0-9_.-]+:[ ]*(\{\})?[ ]*(#.*)?$/ {
      line = $0
      sub(/^[ ]*/, "", line)
      sub(/:.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      if (length(line) > 0) print line
    }
  ' "$_f"
}

# Parse list of repos merged from repo and local configs (order preserved, deduplicated)
yaml_list_repos() {
  _w_y="${WORKSPACE_YAML:-}"
  [ -z "$_w_y" ] && _w_y="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _w_ly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$_w_ly" ] && _w_ly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  {
    _yaml_list_repos_from_file "$_w_y"
    _yaml_list_repos_from_file "$_w_ly"
  } | awk '!seen[$0]++'
}

# Get a field value for a repo from a specific config file
_yaml_get_from_file() {
  _f="$1"; _repo="$2"; _field="$3"
  [ -f "$_f" ] || return 0
  awk -v repo="$_repo" -v field="$_field" '
    /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
    r && /^[^ #]/ { r=0 }
    r && match($0, "^  " repo ":[ ]*(\\{\\})?[ ]*(#.*)?$") { in_target=1; next }
    in_target && /^  [^ #]/ { in_target=0 }
    in_target && match($0, "^    " field ":[ ]*") {
      line = $0
      sub("^    " field ":[ ]*", "", line)
      sub(/[ ]*#.*$/, "", line)
      gsub(/^["\047]|["\047]$/, "", line)
      print line
      exit
    }
  ' "$_f"
}

# Get field value (local config overrides repo config)
yaml_get() {
  _repo="$1"; _field="$2"
  _w_y="${WORKSPACE_YAML:-}"
  [ -z "$_w_y" ] && _w_y="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _w_ly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$_w_ly" ] && _w_ly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  _val="$(_yaml_get_from_file "$_w_ly" "$_repo" "$_field")"
  if [ -n "$_val" ]; then
    printf '%s' "$_val"
    return 0
  fi
  _yaml_get_from_file "$_w_y" "$_repo" "$_field"
}

yaml_has_repo() {
  yaml_list_repos | grep -qx "$1" 2>/dev/null
}

# Check if a repo is enabled: default is true unless explicitly set to false/no/0/disabled
yaml_repo_enabled() {
  _repo="$1"
  _val="$(yaml_get "$_repo" "enabled")"
  _val="$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')"
  case "$_val" in
    false|no|0|disabled|off) return 1 ;;
    *) return 0 ;;
  esac
}

yaml_add_repo() {
  _name="$1"; _url="$2"; _rnex_dir="${3:-true}"; _enabled="${4:-true}"
  if ! grep -q '^repos:' "$WORKSPACE_YAML" 2>/dev/null; then
    printf '\nrepos:\n' >> "$WORKSPACE_YAML"
  fi
  _tmp="$(mktemp)"
  awk -v name="$_name" -v url="$_url" -v rd="$_rnex_dir" -v en="$_enabled" '
    /^repos:/ {
      print
      printf "  %s:\n    url: %s\n", name, url
      if (rd == "false") printf "    rnex_dir: false\n"
      if (en == "false") printf "    enabled: false\n"
      added=1
      next
    }
    { print }
  ' "$WORKSPACE_YAML" > "$_tmp" && mv "$_tmp" "$WORKSPACE_YAML"
}

_yaml_remove_repo_from_file() {
  _file="$1"; _name="$2"
  [ -f "$_file" ] || return 0
  _tmp="$(mktemp)"
  awk -v name="$_name" '
    /^repos:/ { r=1; print; next }
    r && /^[^ #]/ { r=0 }
    r && match($0, "^  " name ":[ ]*(#.*)?$") { skip=1; next }
    r && skip && /^  [^ #]/ { skip=0 }
    skip && /^    / { next }
    { print }
  ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}

yaml_remove_repo() {
  _name="$1"
  _yaml_remove_repo_from_file "$WORKSPACE_YAML" "$_name"
  _yaml_remove_repo_from_file "$WORKSPACE_LOCAL_YAML" "$_name"
}

_yaml_set_in_file() {
  _file="$1"; _repo="$2"; _field="$3"; _value="$4"
  if [ ! -f "$_file" ]; then
    mkdir -p "$(dirname "$_file")"
    printf 'repos:\n' > "$_file"
  elif ! grep -q '^repos:' "$_file" 2>/dev/null; then
    printf '\nrepos:\n' >> "$_file"
  fi

  if ! awk -v repo="$_repo" '
    /^repos:[ ]*$/ || /^repos:[ ]*#/ { in_r=1; next }
    in_r && /^[^ #]/ { in_r=0 }
    in_r && match($0, "^  " repo ":[ ]*(#.*)?$") { found=1; exit }
    END { exit !found }
  ' "$_file" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v repo="$_repo" -v field="$_field" -v value="$_value" '
      /^repos:[ ]*$/ || /^repos:[ ]*#/ {
        print
        printf "  %s:\n    %s: %s\n", repo, field, value
        added=1
        next
      }
      { print }
      END {
        if (!added) {
          printf "repos:\n  %s:\n    %s: %s\n", repo, field, value
        }
      }
    ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
    return 0
  fi

  _tmp="$(mktemp)"
  awk -v repo="$_repo" -v field="$_field" -v value="$_value" '
    /^repos:/ { in_repos=1; print; next }
    in_repos && /^[^ #]/ {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
        field_set=1
      }
      in_repos=0; in_target=0
    }
    in_repos && match($0, "^  " repo ":[ ]*(#.*)?$") {
      in_target=1; print; next
    }
    in_target && /^  [^ #]/ {
      if (!field_set) {
        printf "    %s: %s\n", field, value
        field_set=1
      }
      in_target=0
    }
    in_target && match($0, "^    " field ":") {
      printf "    %s: %s\n", field, value
      field_set=1
      next
    }
    { print }
    END {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
      }
    }
  ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}

yaml_set() {
  _repo="$1"; _field="$2"; _value="$3"
  _yaml_set_in_file "$WORKSPACE_YAML" "$_repo" "$_field" "$_value"
}

yaml_set_local() {
  _repo="$1"; _field="$2"; _value="$3"
  if [ ! -f "$WORKSPACE_LOCAL_YAML" ]; then
    cat <<'EOF' > "$WORKSPACE_LOCAL_YAML"
# ==============================================================================
# .local.rnex.yaml — Repo Nexus Local Configuration (Machine-Specific)
# ==============================================================================
# This file is gitignored. Use it to specify local repository paths, overrides,
# and enable/disable states for this workstation.

repos:
EOF
  fi
  _yaml_set_in_file "$WORKSPACE_LOCAL_YAML" "$_repo" "$_field" "$_value"
}

_yaml_set_top_level_in_file() {
  _file="$1"
  _key="$2"
  _val="$3"
  [ -f "$_file" ] || return 0
  _tmp="$(mktemp)"
  if grep -q "^[ ]*${_key}:" "$_file" 2>/dev/null; then
    awk -v key="$_key" -v val="$_val" '
      $0 ~ ("^[ ]*" key ":") {
        print key ": " val
        next
      }
      { print }
    ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
  else
    awk -v key="$_key" -v val="$_val" '
      BEGIN { inserted=0 }
      /^[ ]*(plugins|repos):/ && !inserted {
        print key ": " val
        print ""
        inserted=1
      }
      { print }
      END {
        if (!inserted) {
          print ""
          print key ": " val
        }
      }
    ' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
  fi
  rm -f "$_tmp"
}

yaml_set_top_level() {
  _key="$1"; _val="$2"
  _yaml_set_top_level_in_file "$WORKSPACE_YAML" "$_key" "$_val"
}

yaml_set_top_level_local() {
  _key="$1"; _val="$2"
  if [ ! -f "$WORKSPACE_LOCAL_YAML" ]; then
    cat <<'EOF' > "$WORKSPACE_LOCAL_YAML"
# ==============================================================================
# .local.rnex.yaml — Repo Nexus Local Configuration (Machine-Specific)
# ==============================================================================
# This file is gitignored. Use it to specify local repository paths, overrides,
# and enable/disable states for this workstation.

EOF
  fi
  _yaml_set_top_level_in_file "$WORKSPACE_LOCAL_YAML" "$_key" "$_val"
}
