#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/yaml.sh — YAML Parser / Manipulator (for rnex.yaml & .local.rnex.yaml)
# ============================================================================

# ---- Config Path & File Initialization Helpers -----------------------------

# Resolve default paths for team workspace configuration (rnex.yaml) and
# local overrides (.local.rnex.yaml) if not already set in the environment.
_yaml_resolve_files() {
  _wy="${WORKSPACE_YAML:-}"
  [ -n "$_wy" ] || _wy="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_CONFIG_FILE:-rnex.yaml}"
  _wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -n "$_wly" ] || _wly="${NEXUS_DIR:-${RNEX_ROOT:-.}}/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
}

# Create a skeletal .local.rnex.yaml file with explanatory comments if it does not yet exist.
_ensure_local_yaml_file() {
  _ely_sec="${1:-}"
  if [ ! -f "$WORKSPACE_LOCAL_YAML" ]; then
    cat <<EOF > "$WORKSPACE_LOCAL_YAML"
# ==============================================================================
# .local.rnex.yaml — Repo Nexus Local Configuration (Machine-Specific)
# ==============================================================================
# This file is gitignored. Use it to specify local repository paths, overrides,
# and enable/disable states for this workstation.
${_ely_sec:+
${_ely_sec}:}
EOF
  fi
}

# ---- Generic Top-Level & Section YAML Primitives ---------------------------

# Read a top-level scalar property matching a regex pattern from a YAML file.
# Strips surrounding whitespace, comments, and quotes using awk.
_yaml_top_level_from_file() {
  _ytf_f="$1"; _ytf_pat="$2"
  [ -f "$_ytf_f" ] || return 0
  awk -v pat="^(${_ytf_pat})[ \t]*:" '
    $0 ~ pat {
      line = $0
      sub(/^[a-zA-Z0-9_.-]+[ \t]*:[ \t]*/, "", line)
      sub(/[ \t]*#.*/, "", line)
      sub(/^[ \t]+/, "", line)
      sub(/[ \t\r]+$/, "", line)
      gsub(/^["\047]|["\047]$/, "", line)
      val = line
    }
    END { if (length(val) > 0) print val }
  ' "$_ytf_f"
}

# Read a top-level configuration key, checking .local.rnex.yaml first (local override),
# then falling back to rnex.yaml, and finally the provided default value.
yaml_get_top_level() {
  _ygt_pat="$1"; _ygt_def="${2:-}"
  _yaml_resolve_files
  _ygt_val="$(_yaml_top_level_from_file "$_wly" "$_ygt_pat")"
  [ -n "$_ygt_val" ] || _ygt_val="$(_yaml_top_level_from_file "$_wy" "$_ygt_pat")"
  if [ -n "$_ygt_val" ]; then
    printf '%s' "$_ygt_val"
  elif [ -n "$_ygt_def" ]; then
    printf '%s' "$_ygt_def"
  fi
}

# Extract all item keys defined under a given top-level section (e.g., 'repos' or 'plugins').
# Handles map items ("  name:") and list items ("  - name").
_yaml_section_keys() {
  _ysk_f="$1"; _ysk_sec="$2"
  [ -f "$_ysk_f" ] || return 0
  awk -v sec="$_ysk_sec" '
    $0 ~ ("^[ \t]*" sec ":[ \t]*(#.*)?$") { in_sec=1; sec_indent=-1; next }
    in_sec && /^[^ \t#]/ { in_sec=0 }
    !in_sec { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_sec && (sec_indent == -1) && (indent > 0) {
      sec_indent = indent
    }

    in_sec && (indent == sec_indent) {
      if (trimmed ~ /^["\047]?[a-zA-Z0-9_.-]+["\047]?:/) {
        line = trimmed
        sub(/:.*/, "", line)
        gsub(/^["\047]|["\047]$/, "", line)
        gsub(/[[:space:]]/, "", line)
        if (length(line) > 0) print line
      } else if (sec == "plugins" && trimmed ~ /^-[ \t]+["\047]?[a-zA-Z0-9_.-]+/) {
        line = trimmed
        sub(/^-[ \t]+/, "", line)
        sub(/[ \t]*#.*/, "", line)
        sub(/:.*/, "", line)
        gsub(/^["\047]|["\047]$/, "", line)
        gsub(/[[:space:]]/, "", line)
        if (length(line) > 0) print line
      }
    }
  ' "$_ysk_f"
}

# Read the value of a specific property ($key) within an item ($item) of a section ($sec).
# Example: _yaml_section_get "rnex.yaml" "repos" "backend" "url"
_yaml_section_get() {
  _ysg_f="$1"; _ysg_sec="$2"; _ysg_item="$3"; _ysg_key="$4"
  [ -f "$_ysg_f" ] || return 0
  awk -v sec="$_ysg_sec" -v item="$_ysg_item" -v key="$_ysg_key" '
    $0 ~ ("^[ \t]*" sec ":[ \t]*(#.*)?$") { in_sec=1; in_target=0; item_indent=-1; next }
    in_sec && /^[^ \t#]/ { in_sec=0; in_target=0 }
    !in_sec { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_target && (indent <= item_indent) {
      in_target=0
    }

    !in_target {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == item && trimmed ~ /:[ \t]*(\{\})?[ \t]*(#.*)?$/) {
        in_target=1
        item_indent=indent
        next
      }
    }

    in_target && (indent > item_indent) {
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
  ' "$_ysg_f"
}

# Update or insert a key-value property ($field: $value) under a specific item ($item)
# within a top-level section ($sec). Preserves comments and formatting.
_yaml_section_set() {
  _yss_file="$1"; _yss_sec="$2"; _yss_item="$3"; _yss_field="$4"; _yss_value="$5"
  if [ ! -f "$_yss_file" ]; then
    mkdir -p "$(dirname "$_yss_file")"
    printf '%s:\n' "$_yss_sec" > "$_yss_file"
  elif ! grep -q "^${_yss_sec}:" "$_yss_file" 2>/dev/null; then
    printf '\n%s:\n' "$_yss_sec" >> "$_yss_file"
  fi

  if ! awk -v sec="$_yss_sec" -v item="$_yss_item" '
    $0 ~ ("^" sec ":[ ]*$") || $0 ~ ("^" sec ":[ ]*#") { in_s=1; next }
    in_s && /^[^ #]/ { in_s=0 }
    in_s && match($0, "^  " item ":[ ]*(#.*)?$") { found=1; exit }
    END { exit !found }
  ' "$_yss_file" 2>/dev/null; then
    if grep -qE "^  $_yss_item:[ ]*(\{\}|\[\])?$" "$_yss_file" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v item="$_yss_item" -v field="$_yss_field" -v value="$_yss_value" '
        match($0, "^  " item ":[ ]*(\\{\\}|\\[\\])?$") {
          printf "  %s:\n    %s: %s\n", item, field, value
          next
        }
        { print }
      ' "$_yss_file" > "$_tmp" && mv "$_tmp" "$_yss_file"
      return 0
    fi
    _tmp="$(mktemp)"
    awk -v sec="$_yss_sec" -v item="$_yss_item" -v field="$_yss_field" -v value="$_yss_value" '
      $0 ~ ("^" sec ":[ ]*$") || $0 ~ ("^" sec ":[ ]*#") {
        print
        printf "  %s:\n    %s: %s\n", item, field, value
        added=1
        next
      }
      { print }
      END {
        if (!added) {
          printf "%s:\n  %s:\n    %s: %s\n", sec, item, field, value
        }
      }
    ' "$_yss_file" > "$_tmp" && mv "$_tmp" "$_yss_file"
    return 0
  fi

  _tmp="$(mktemp)"
  awk -v sec="$_yss_sec" -v item="$_yss_item" -v field="$_yss_field" -v value="$_yss_value" '
    $0 ~ ("^" sec ":") { in_sec=1; print; next }
    in_sec && /^[^ #]/ {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
        field_set=1
      }
      in_sec=0; in_target=0
    }
    in_sec && match($0, "^  " item ":[ ]*(#.*)?$") {
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
  ' "$_yss_file" > "$_tmp" && mv "$_tmp" "$_yss_file"
}

_yaml_section_remove() {
  _ysr_file="$1"; _ysr_sec="$2"; _ysr_name="$3"
  [ -f "$_ysr_file" ] || return 0
  _tmp="$(mktemp)"
  awk -v sec="$_ysr_sec" -v name="$_ysr_name" '
    $0 ~ ("^" sec ":") { in_sec=1; print; next }
    in_sec && /^[^ #]/ { in_sec=0; skip=0 }
    in_sec && match($0, "^  " name ":[ ]*(\\{\\})?[ ]*(#.*)?$") { skip=1; next }
    in_sec && skip && /^  [^ #]/ { skip=0 }
    skip && /^    / { next }
    { print }
  ' "$_ysr_file" > "$_tmp" && mv "$_tmp" "$_ysr_file"
}

# ---- Plugin Configuration Operations ---------------------------------------

_yaml_list_plugins_from_file() {
  _yaml_section_keys "$1" "plugins"
}

yaml_list_plugins() {
  _yaml_resolve_files
  {
    _yaml_list_plugins_from_file "$_wy"
    _yaml_list_plugins_from_file "$_wly"
  } | awk '!seen[$0]++'
}

_yaml_plugin_get_from_file() {
  _yaml_section_get "$1" "plugins" "$2" "$3"
}

yaml_plugin_get() {
  _pname="$1"; _key="$2"
  _yaml_resolve_files
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
  _yaml_resolve_files

  _gpl_items="$(_yaml_plugin_list_from_file "$_wly" "$_gpl_plugin" "$_gpl_key")"
  [ -n "$_gpl_items" ] || _gpl_items="$(_yaml_plugin_list_from_file "$_wy" "$_gpl_plugin" "$_gpl_key")"
  if [ -n "$_gpl_items" ]; then
    printf '%s\n' "$_gpl_items"
    return 0
  fi

  case "$_gpl_plugin:$_gpl_key" in
    karpathy-llm:sources)
      _gpl_raw="$(plugin_legacy_raw_dir "$_gpl_plugin")"
      if [ -n "$_gpl_raw" ]; then
        log_warn "plugins.$_gpl_plugin.raw_dir is deprecated; run 'rnex sync' to rewrite it to 'sources' in ${RNEX_CONFIG_FILE:-rnex.yaml}." >&2
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
  _yaml_resolve_files
  [ -n "$(_yaml_plugin_list_from_file "$_wly" "$_plr_plugin" "sources")" ] && return 0
  [ -n "$(_yaml_plugin_list_from_file "$_wy" "$_plr_plugin" "sources")" ] && return 0
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
  is_enabled_val "$(yaml_plugin_get "$_plugin" "enabled")"
}

provider_plugin_enabled() {
  yaml_plugin_enabled "$1"
}

provider_option_enabled() {
  _p="$1"; _opt="$2"
  provider_plugin_enabled "$_p" || return 1
  is_enabled_val "$(yaml_plugin_get "$_p" "$_opt")"
}

provider_auto_sync_enabled() {
  _p="$1"
  provider_plugin_enabled "$_p" || return 1
  _val="$(yaml_plugin_get "$_p" "auto_sync_on")"
  [ -n "$_val" ] || _val="$(yaml_plugin_get "$_p" "autoSyncOn")"
  [ -n "$_val" ] || _val="SessionStart"
  is_enabled_val "$_val"
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

codex_plugin_enabled() { provider_plugin_enabled "codex"; }
codex_instructions_enabled() { provider_plugin_enabled "codex"; }
codex_skills_enabled() { provider_option_enabled "codex" "skills"; }

has_active_provider_instructions() {
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
     windsurf_instructions_enabled || \
     codex_instructions_enabled; then
    _res=0
  fi
  if [ -n "$1" ] && [ -d "$1" ]; then
    WORKSPACE_YAML="$_saved_ws_yaml"
    WORKSPACE_LOCAL_YAML="$_saved_local_yaml"
  fi
  return $_res
}

_yaml_plugin_set_in_file() {
  _yaml_section_set "$1" "plugins" "$2" "$3" "$4"
}

yaml_plugin_set() {
  _yaml_plugin_set_in_file "$WORKSPACE_YAML" "$1" "$2" "$3"
}

yaml_plugin_set_local() {
  _ensure_local_yaml_file "plugins"
  _yaml_plugin_set_in_file "$WORKSPACE_LOCAL_YAML" "$1" "$2" "$3"
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
  _yaml_section_remove "$1" "plugins" "$2"
}

yaml_disable_plugin() {
  _name="$1"
  _yaml_disable_plugin_in_file "$WORKSPACE_YAML" "$_name"
  _yaml_disable_plugin_in_file "$WORKSPACE_LOCAL_YAML" "$_name"
}

# ---- Repository Configuration Operations -----------------------------------

# Parse list of repos from a single config file
_yaml_list_repos_from_file() {
  _yaml_section_keys "$1" "repos"
}

# Parse list of repos merged from repo and local configs (order preserved, deduplicated)
yaml_list_repos() {
  _yaml_resolve_files
  {
    _yaml_list_repos_from_file "$_wy"
    _yaml_list_repos_from_file "$_wly"
  } | awk '!seen[$0]++'
}

# Get a field value for a repo from a specific config file
_yaml_get_from_file() {
  _yaml_section_get "$1" "repos" "$2" "$3"
}

# Get field value (local config overrides repo config)
yaml_get() {
  _repo="$1"; _field="$2"
  _yaml_resolve_files
  _val="$(_yaml_get_from_file "$_wly" "$_repo" "$_field")"
  if [ -n "$_val" ]; then
    printf '%s' "$_val"
    return 0
  fi
  _yaml_get_from_file "$_wy" "$_repo" "$_field"
}

yaml_has_repo() {
  yaml_list_repos | grep -qx "$1" 2>/dev/null
}

# Check if a repo is enabled: default is true unless explicitly set to false/no/0/disabled
yaml_repo_enabled() {
  is_enabled_val "$(yaml_get "$1" "enabled")"
}

# Check if a repo is readonly: default is false unless explicitly set to true/yes/1
yaml_repo_readonly() {
  is_truthy "$(yaml_get "$1" "readonly")"
}

# Add a new repository entry under 'repos:' in the main workspace configuration (rnex.yaml).
yaml_add_repo() {
  _name="$1"; _url="$2"; _enabled="${3:-true}"; _readonly="${4:-false}"
  if ! grep -q '^repos:' "$WORKSPACE_YAML" 2>/dev/null; then
    printf '\nrepos:\n' >> "$WORKSPACE_YAML"
  fi
  _tmp="$(mktemp)"
  awk -v name="$_name" -v url="$_url" -v en="$_enabled" -v ro="$_readonly" '
    /^repos:/ {
      print
      printf "  %s:\n    url: %s\n", name, url
      if (en == "false") printf "    enabled: false\n"
      if (ro == "true") printf "    readonly: true\n"
      added=1
      next
    }
    { print }
  ' "$WORKSPACE_YAML" > "$_tmp" && mv "$_tmp" "$WORKSPACE_YAML"
}

_yaml_remove_repo_from_file() {
  _yaml_section_remove "$1" "repos" "$2"
}

# Remove a repository entry from both rnex.yaml and .local.rnex.yaml.
yaml_remove_repo() {
  _name="$1"
  _yaml_remove_repo_from_file "$WORKSPACE_YAML" "$_name"
  _yaml_remove_repo_from_file "$WORKSPACE_LOCAL_YAML" "$_name"
}

_yaml_set_in_file() {
  _yaml_section_set "$1" "repos" "$2" "$3" "$4"
}

# Set a field value for a repo in team config (rnex.yaml).
yaml_set() {
  _yaml_set_in_file "$WORKSPACE_YAML" "$1" "$2" "$3"
}

# Set a field value for a repo in local machine config (.local.rnex.yaml).
yaml_set_local() {
  _ensure_local_yaml_file "repos"
  _yaml_set_in_file "$WORKSPACE_LOCAL_YAML" "$1" "$2" "$3"
}

# ---- Top-Level Key Setters -------------------------------------------------

# Set a top-level key/value pair in a specific YAML file, inserting before 'plugins:' or 'repos:'.
_yaml_set_top_level_in_file() {
  _file="$1"; _key="$2"; _val="$3"
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
  _yaml_set_top_level_in_file "$WORKSPACE_YAML" "$1" "$2"
}

yaml_set_top_level_local() {
  _ensure_local_yaml_file ""
  _yaml_set_top_level_in_file "$WORKSPACE_LOCAL_YAML" "$1" "$2"
}
