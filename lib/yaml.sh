#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/yaml.sh — YAML Parser / Manipulator (for rnex.yaml & .local.rnex.yaml)
# ============================================================================

_yaml_list_plugins_from_file() {
  _f="$1"
  [ -f "$_f" ] || return 0
  awk '
    /^plugins:[ ]*$/ || /^plugins:[ ]*#/ { p=1; next }
    p && /^[^ #]/ { p=0 }
    p && /^  [a-zA-Z0-9_.-]+:/ {
      line = $0
      sub(/^[ ]*/, "", line)
      sub(/:.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      if (length(line) > 0) print line
    }
    p && /^  -[ ]+[a-zA-Z0-9_.-]+/ {
      line = $0
      sub(/^[ ]*-[ ]*/, "", line)
      sub(/[ ]*#.*/, "", line)
      sub(/:.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      if (length(line) > 0) print line
    }
  ' "$_f"
}

yaml_list_plugins() {
  {
    _yaml_list_plugins_from_file "$WORKSPACE_YAML"
    _yaml_list_plugins_from_file "$WORKSPACE_LOCAL_YAML"
  } | awk '!seen[$0]++'
}

_yaml_plugin_get_from_file() {
  _f="$1"; _pname="$2"; _key="$3"
  [ -f "$_f" ] || return 0
  awk -v plugin="$_pname" -v key="$_key" '
    /^plugins:[ ]*$/ || /^plugins:[ ]*#/ { in_plugins=1; next }
    in_plugins && /^[^ #]/ { in_plugins=0 }
    in_plugins && match($0, "^  " plugin ":[ ]*(#.*)?$") { in_target=1; next }
    in_target && /^  [^ #]/ { in_target=0 }
    in_target && match($0, "^    " key ":[ ]*") {
      line = $0
      sub("^    " key ":[ ]*", "", line)
      sub(/[ ]*#.*$/, "", line)
      gsub(/^["\x27]|["\x27]$/, "", line)
      print line
      exit
    }
  ' "$_f"
}

yaml_plugin_get() {
  _pname="$1"; _key="$2"
  _val="$(_yaml_plugin_get_from_file "$WORKSPACE_LOCAL_YAML" "$_pname" "$_key")"
  if [ -n "$_val" ]; then
    printf '%s' "$_val"
    return 0
  fi
  _yaml_plugin_get_from_file "$WORKSPACE_YAML" "$_pname" "$_key"
}

yaml_plugin_list_config() {
  _pname="$1"
  _f="$WORKSPACE_YAML"
  [ -f "$_f" ] || return 0
  awk -v plugin="$_pname" '
    /^plugins:[ ]*$/ || /^plugins:[ ]*#/ { in_plugins=1; next }
    in_plugins && /^[^ #]/ { in_plugins=0 }
    in_plugins && match($0, "^  " plugin ":[ ]*(#.*)?$") { in_target=1; next }
    in_target && /^  [^ #]/ { in_target=0 }
    in_target && /^    [a-zA-Z0-9_.-]+:[ ]*/ {
      line = $0
      sub(/^[ ]*/, "", line)
      sub(/[ ]*#.*$/, "", line)
      print line
    }
  ' "$_f"
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

copilot_plugin_enabled() { provider_plugin_enabled "copilot"; }
copilot_instructions_enabled() { provider_option_enabled "copilot" "instructions"; }
copilot_skills_enabled() { provider_option_enabled "copilot" "skills"; }
copilot_agents_enabled() { return 1; }

claude_plugin_enabled() { provider_plugin_enabled "claude"; }
claude_instructions_enabled() { provider_option_enabled "claude" "instructions"; }
claude_skills_enabled() { provider_option_enabled "claude" "skills"; }
claude_agents_enabled() { return 1; }

gemini_plugin_enabled() { provider_plugin_enabled "gemini"; }
gemini_instructions_enabled() { provider_option_enabled "gemini" "instructions"; }
gemini_skills_enabled() { provider_option_enabled "gemini" "skills"; }
gemini_agents_enabled() { return 1; }

cursor_plugin_enabled() { provider_plugin_enabled "cursor"; }
cursor_instructions_enabled() { provider_option_enabled "cursor" "instructions"; }
cursor_skills_enabled() { provider_option_enabled "cursor" "skills"; }
cursor_agents_enabled() { return 1; }

windsurf_plugin_enabled() { provider_plugin_enabled "windsurf"; }
windsurf_instructions_enabled() { provider_option_enabled "windsurf" "instructions"; }
windsurf_skills_enabled() { provider_option_enabled "windsurf" "skills"; }
windsurf_agents_enabled() { return 1; }

has_ai_provider_plugin_enabled() {
  for _ap in copilot claude gemini cursor windsurf; do
    if provider_plugin_enabled "$_ap"; then
      return 0
    fi
  done
  return 1
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
    _tmp="$(mktemp)"
    case "$_name" in
      copilot|claude|gemini|cursor|windsurf)
        awk -v name="$_name" '
          /^plugins:[ ]*$/ || /^plugins:[ ]*#/ {
            print
            printf "  %s:\n    instructions: true\n    skills: true\n", name
            added=1
            next
          }
          { print }
          END {
            if (!added) {
              printf "plugins:\n  %s:\n    instructions: true\n    skills: true\n", name
            }
          }
        ' "$_target_file" > "$_tmp" && mv "$_tmp" "$_target_file"
        ;;
      karpathy-llm)
        awk -v name="$_name" '
          /^plugins:[ ]*$/ || /^plugins:[ ]*#/ {
            print
            printf "  %s:\n    raw_dir: \"./docs\"\n    wiki_dir: \".rnex/wiki\"\n    lint_trigger: \"manual\"\n    ingest_member_readmes: true\n", name
            added=1
            next
          }
          { print }
          END {
            if (!added) {
              printf "plugins:\n  %s:\n    raw_dir: \"./docs\"\n    wiki_dir: \".rnex/wiki\"\n    lint_trigger: \"manual\"\n    ingest_member_readmes: true\n", name
            }
          }
        ' "$_target_file" > "$_tmp" && mv "$_tmp" "$_target_file"
        ;;
      *)
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
        ;;
    esac
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
    r && /^  [a-zA-Z0-9_.-]+:[ ]*(#.*)?$/ {
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
  {
    _yaml_list_repos_from_file "$WORKSPACE_YAML"
    _yaml_list_repos_from_file "$WORKSPACE_LOCAL_YAML"
  } | awk '!seen[$0]++'
}

# Get a field value for a repo from a specific config file
_yaml_get_from_file() {
  _f="$1"; _repo="$2"; _field="$3"
  [ -f "$_f" ] || return 0
  awk -v repo="$_repo" -v field="$_field" '
    /^repos:[ ]*$/ || /^repos:[ ]*#/ { r=1; next }
    r && /^[^ #]/ { r=0 }
    r && match($0, "^  " repo ":[ ]*(#.*)?$") { in_target=1; next }
    in_target && /^  [^ #]/ { in_target=0 }
    in_target && match($0, "^    " field ":[ ]*") {
      line = $0
      sub("^    " field ":[ ]*", "", line)
      sub(/[ ]*#.*$/, "", line)
      gsub(/^["\x27]|["\x27]$/, "", line)
      print line
      exit
    }
  ' "$_f"
}

# Get field value (local config overrides repo config)
yaml_get() {
  _repo="$1"; _field="$2"
  _val="$(_yaml_get_from_file "$WORKSPACE_LOCAL_YAML" "$_repo" "$_field")"
  if [ -n "$_val" ]; then
    printf '%s' "$_val"
    return 0
  fi
  _yaml_get_from_file "$WORKSPACE_YAML" "$_repo" "$_field"
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
