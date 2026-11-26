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

# ---- Shared AWK Snippets (DRY Primitives) ----------------------------------

# Shared POSIX AWK unquote function: strips surrounding whitespace, quotes, and inline comments.
# shellcheck disable=SC2016
_YAML_AWK_UNQUOTE='
function unquote(v) {
  sub(/^[ \t]+/, "", v)
  if (v ~ /^"/) {
    sub(/^"/, "", v)
    sub(/"[ \t]*(#.*)?$/, "", v)
  } else if (v ~ /^\047/) {
    sub(/^\047/, "", v)
    sub(/\047[ \t]*(#.*)?$/, "", v)
  } else {
    sub(/[ \t]+#.*$/, "", v)
    sub(/[ \t]+$/, "", v)
  }
  return v
}
'

# Shared POSIX AWK list item cleaner and quote-aware inline flow array parser.
# shellcheck disable=SC2016
_YAML_AWK_LIST_LIB='
function clean_item(v) {
  sub(/^[ \t]+/, "", v)
  if (v ~ /^"[^"]*"/) {
    match(v, /^"[^"]*"/)
    v = substr(v, 2, RLENGTH - 2)
  } else if (v ~ /^\047[^\047]*\047/) {
    match(v, /^\047[^\047]*\047/)
    v = substr(v, 2, RLENGTH - 2)
  } else {
    sub(/[ \t]*#.*$/, "", v)
    sub(/[ \t]+$/, "", v)
    sub(/^["\047]/, "", v)
    sub(/["\047]$/, "", v)
  }
  sub(/^[ \t]+/, "", v)
  sub(/[ \t]+$/, "", v)
  sub(/^\.\//, "", v)
  return v
}

function parse_inline_array(str,   len, in_dquote, in_squote, curr, i, c, item) {
  len = length(str)
  in_dquote = 0
  in_squote = 0
  curr = ""
  for (i = 1; i <= len; i++) {
    c = substr(str, i, 1)
    if (c == "\"" && !in_squote) {
      in_dquote = !in_dquote
      curr = curr c
    } else if (c == "\047" && !in_dquote) {
      in_squote = !in_squote
      curr = curr c
    } else if (c == "," && !in_dquote && !in_squote) {
      item = clean_item(curr)
      if (length(item) > 0) print item
      curr = ""
    } else {
      curr = curr c
    }
  }
  if (length(curr) > 0) {
    item = clean_item(curr)
    if (length(item) > 0) print item
  }
}
'

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
      if (line ~ /^\{/) { val = ""; next }
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

# Read the top-level reposDir setting from .local.rnex.yaml or rnex.yaml.
# Normalizes relative paths (stripping leading './' and trailing slashes).
# Enforces safe directory paths (preventing path traversal escaping workspace root).
# Defaults to "repos" if unset, empty, or invalid.
yaml_get_repos_dir() {
  _yaml_resolve_files
  _ygrd_val="$(_yaml_top_level_from_file "$_wly" "reposDir")"
  [ -n "$_ygrd_val" ] || _ygrd_val="$(_yaml_top_level_from_file "$_wy" "reposDir")"

  # Strip surrounding whitespace
  while :; do
    case "$_ygrd_val" in
      [[:space:]]*) _ygrd_val="${_ygrd_val#[[:space:]]}" ;;
      *[[:space:]]) _ygrd_val="${_ygrd_val%[[:space:]]}" ;;
      *) break ;;
    esac
  done

  if command -v clean_rel_subpath >/dev/null 2>&1; then
    _ygrd_val="$(clean_rel_subpath "$_ygrd_val")"
  else
    while [ "${_ygrd_val#./}" != "$_ygrd_val" ]; do _ygrd_val="${_ygrd_val#./}"; done
    while [ "$_ygrd_val" != "${_ygrd_val%/}" ] && [ -n "${_ygrd_val%/}" ]; do _ygrd_val="${_ygrd_val%/}"; done
  fi

  # Security / validation: reject empty, '.', absolute paths, or path traversal escaping workspace root
  case "$_ygrd_val" in
    ''|.|/*|..|../*|*/..|*/../*)
      _ygrd_val="repos"
      ;;
  esac

  printf '%s' "$_ygrd_val"
}

# Return the absolute path to the member repositories root folder
get_repos_root() {
  _grr_dir="${NEXUS_DIR:-${RNEX_ROOT:-.}}"
  printf '%s/%s' "$_grr_dir" "$(yaml_get_repos_dir)"
}

# Resolve filesystem path for a specific member repository
get_repo_path() {
  _grp_name="$1"
  _grp_custom="$(yaml_get "$_grp_name" "path" 2>/dev/null || true)"
  if [ -n "$_grp_custom" ]; then
    case "$_grp_custom" in
      /*) printf '%s' "$_grp_custom" ;;
      *)  printf '%s/%s' "${NEXUS_DIR:-${RNEX_ROOT:-.}}" "$_grp_custom" ;;
    esac
  else
    printf '%s/%s' "$(get_repos_root)" "$_grp_name"
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
# within a top-level section ($sec). Matches keys literally (safe for names containing '.')
# and passes values via ENVIRON to preserve backslashes.
_yaml_section_set() {
  _yss_file="$1"; _yss_sec="$2"; _yss_item="$3"; _yss_field="$4"; _yss_value="$5"
  if [ ! -f "$_yss_file" ]; then
    mkdir -p "$(dirname "$_yss_file")"
    printf '%s:\n' "$_yss_sec" > "$_yss_file"
  elif ! grep -q "^${_yss_sec}:" "$_yss_file" 2>/dev/null; then
    printf '\n%s:\n' "$_yss_sec" >> "$_yss_file"
  fi

  if ! _YSS_SEC="$_yss_sec" _YSS_ITEM="$_yss_item" awk '
    BEGIN { sec = ENVIRON["_YSS_SEC"]; item = ENVIRON["_YSS_ITEM"] }
    /^[^ #]/ {
      hdr = $0; sub(/:[ ]*(#.*)?$/, "", hdr)
      in_s = (hdr == sec && $0 ~ /^[^:]+:[ ]*(#.*)?$/)
      next
    }
    in_s && /^  [^ #]/ {
      k = substr($0, 3); sub(/:.*/, "", k)
      if (k == item && $0 ~ /^  [^:]+:[ ]*(#.*)?$/) { found = 1; exit }
    }
    END { exit !found }
  ' "$_yss_file" 2>/dev/null; then
    if _YSS_ITEM="$_yss_item" awk '
      BEGIN { item = ENVIRON["_YSS_ITEM"] }
      /^  [^ #]/ {
        k = substr($0, 3); sub(/:.*/, "", k)
        if (k == item && $0 ~ /^  [^:]+:[ ]*(\{\}|\[\])?[ ]*(#.*)?$/) { found = 1; exit }
      }
      END { exit !found }
    ' "$_yss_file" 2>/dev/null; then
      _tmp="$(mktemp)"
      _YSS_ITEM="$_yss_item" _YSS_FIELD="$_yss_field" _YSS_VAL="$_yss_value" awk '
        BEGIN { item = ENVIRON["_YSS_ITEM"]; field = ENVIRON["_YSS_FIELD"]; value = ENVIRON["_YSS_VAL"] }
        /^  [^ #]/ {
          k = substr($0, 3); sub(/:.*/, "", k)
          if (k == item && $0 ~ /^  [^:]+:[ ]*(\{\}|\[\])?[ ]*(#.*)?$/) {
            printf "  %s:\n    %s: %s\n", item, field, value
            next
          }
        }
        { print }
      ' "$_yss_file" > "$_tmp" && mv "$_tmp" "$_yss_file"
      return 0
    fi
    _tmp="$(mktemp)"
    _YSS_SEC="$_yss_sec" _YSS_ITEM="$_yss_item" _YSS_FIELD="$_yss_field" _YSS_VAL="$_yss_value" awk '
      BEGIN { sec = ENVIRON["_YSS_SEC"]; item = ENVIRON["_YSS_ITEM"]; field = ENVIRON["_YSS_FIELD"]; value = ENVIRON["_YSS_VAL"] }
      !added && /^[^ #]/ {
        hdr = $0; sub(/:[ ]*(#.*)?$/, "", hdr)
        if (hdr == sec && $0 ~ /^[^:]+:[ ]*(#.*)?$/) {
          print
          printf "  %s:\n    %s: %s\n", item, field, value
          added = 1
          next
        }
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
  _YSS_SEC="$_yss_sec" _YSS_ITEM="$_yss_item" _YSS_FIELD="$_yss_field" _YSS_VAL="$_yss_value" awk '
    BEGIN { sec = ENVIRON["_YSS_SEC"]; item = ENVIRON["_YSS_ITEM"]; field = ENVIRON["_YSS_FIELD"]; value = ENVIRON["_YSS_VAL"] }
    /^[^ #]/ {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
        field_set = 1
      }
      hdr = $0; sub(/:.*/, "", hdr)
      in_sec = (hdr == sec)
      in_target = 0
      print
      next
    }
    in_sec && /^  [^ #]/ {
      if (in_target && !field_set) {
        printf "    %s: %s\n", field, value
        field_set = 1
      }
      k = substr($0, 3); sub(/:.*/, "", k)
      if (k == item && $0 ~ /^  [^:]+:[ ]*(#.*)?$/) {
        in_target = 1
        print
        next
      }
      in_target = 0
    }
    in_target && /^    [^ #]/ {
      fk = substr($0, 5); sub(/:.*/, "", fk)
      if (fk == field) {
        printf "    %s: %s\n", field, value
        field_set = 1
        next
      }
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
  _YSR_SEC="$_ysr_sec" _YSR_NAME="$_ysr_name" awk '
    BEGIN { sec = ENVIRON["_YSR_SEC"]; name = ENVIRON["_YSR_NAME"] }
    /^[^ #]/ {
      hdr = $0; sub(/:.*/, "", hdr)
      in_sec = (hdr == sec)
      skip = 0
      print
      next
    }
    in_sec && /^  [^ #]/ {
      k = substr($0, 3); sub(/:.*/, "", k)
      if (k == name && $0 ~ /^  [^:]+:[ ]*(\{\})?[ ]*(#.*)?$/) {
        skip = 1
        next
      }
      skip = 0
    }
    skip && /^    / { next }
    { print }
  ' "$_ysr_file" > "$_tmp" && mv "$_tmp" "$_ysr_file"
}

# ---- Git Configuration Operations (git.ignore & git.hooks) -----------------

# Extract list items under git.ignore from a YAML file.
_yaml_git_ignore_from_file() {
  _ygif_f="$1"
  [ -f "$_ygif_f" ] || return 0
  awk "${_YAML_AWK_UNQUOTE}"'
    /^[ \t]*git:[ \t]*(#.*)?$/ { in_git=1; in_ignore=0; next }
    in_git && /^[^ \t#]/ { exit }
    !in_git { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_ignore {
      if (indent > ignore_indent || (indent == ignore_indent && trimmed ~ /^-([ \t]|$)/)) {
        if (trimmed ~ /^-([ \t]|$)/) {
          item = unquote(substr(trimmed, 2))
          if (length(item) > 0) print item
        }
        next
      }
      in_ignore = 0
    }

    !in_ignore {
      if (trimmed ~ /^ignore:[ \t]*/) {
        ignore_indent = indent
        val = trimmed
        sub(/^ignore:[ \t]*/, "", val)
        if (val ~ /^(#.*)?$/) {
          in_ignore = 1
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
    }
  ' "$_ygif_f"
}

# Read list items under git.ignore merged from rnex.yaml and .local.rnex.yaml.
yaml_get_git_ignore() {
  _yaml_resolve_files
  {
    _yaml_git_ignore_from_file "$_wy"
    _yaml_git_ignore_from_file "$_wly"
  } | awk '!seen[$0]++'
}

# Parse Git hook declarations under git.hooks from a single YAML file, filtering by state.
# Supports nested maps (git.hooks.<hook>: [cmds] | false | enabled: false), block sequences,
# and inline arrays.
#
# @param $1 Path to YAML file.
# @param $2 Filter mode: "enabled" (default) or "disabled".
# @returns Newline-delimited list of matching hook names.
# @pure
_yaml_parse_git_hooks_by_state() {
  _ypghs_f="$1"
  _ypghs_mode="${2:-enabled}"
  [ -f "$_ypghs_f" ] || return 0
  awk -v mode="$_ypghs_mode" "${_YAML_AWK_UNQUOTE}"'
    /^[ \t]*git:[ \t]*(#.*)?$/ { in_git=1; next }
    in_git && /^[^ \t#]/ { exit }
    !in_git { next }

    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_hooks && (indent <= hooks_indent) { in_hooks=0 }

    !in_hooks {
      if (trimmed ~ /^hooks:[ \t]*/) {
        in_hooks = 1
        hooks_indent = indent
        hook_item_indent = -1
        current_hook = ""
        val = trimmed
        sub(/^hooks:[ \t]*/, "", val)
        val = unquote(val)
        if (val ~ /^\[/) {
          sub(/^\[/, "", val)
          sub(/\][ \t]*(#.*)?$/, "", val)
          n = split(val, parts, ",")
          for (i = 1; i <= n; i++) {
            item = unquote(parts[i])
            if (item ~ /^[a-z][a-z0-9-]*$/) {
              if (!(item in hook_seen)) {
                hook_seen[item] = 1
                hook_names[++hook_count] = item
              }
              hook_enabled[item] = 1
            }
          }
          in_hooks = 0
        }
      }
      next
    }

    in_hooks {
      if (hook_item_indent == -1) {
        hook_item_indent = indent
      }

      if (indent == hook_item_indent) {
        if (trimmed ~ /^-([ \t]|$)/) {
          current_hook = ""
          item = unquote(substr(trimmed, 2))
          if (item ~ /^[a-z][a-z0-9-]*$/) {
            if (!(item in hook_seen)) {
              hook_seen[item] = 1
              hook_names[++hook_count] = item
            }
            hook_enabled[item] = 1
          }
          next
        }

        if (trimmed ~ /^[a-z0-9"\047][^:]*:[ \t]*/) {
          k = trimmed
          sub(/:.*/, "", k)
          k = unquote(k)
          if (k ~ /^[a-z][a-z0-9-]*$/) {
            current_hook = k
            if (!(k in hook_seen)) {
              hook_seen[k] = 1
              hook_names[++hook_count] = k
            }
            val = trimmed
            sub(/^[^:]*:[ \t]*/, "", val)
            val = unquote(val)
            if (val == "false" || val ~ /^\{[ \t]*enabled:[ \t]*false[ \t]*\}/) {
              hook_enabled[k] = 0
            } else {
              hook_enabled[k] = 1
            }
          } else {
            current_hook = ""
          }
          next
        }
      }

      if (current_hook != "" && indent > hook_item_indent) {
        if (trimmed ~ /^enabled:[ \t]*false([ \t]|$|#)/) {
          hook_enabled[current_hook] = 0
        }
      }
    }

    END {
      want = (mode == "disabled") ? 0 : 1
      for (i = 1; i <= hook_count; i++) {
        h = hook_names[i]
        if (hook_enabled[h] == want) {
          print h
        }
      }
    }
  ' "$_ypghs_f"
}

# Extract list of enabled hook names defined under git.hooks from a single YAML file.
_yaml_parse_git_hooks_from_file() {
  _yaml_parse_git_hooks_by_state "$1" "enabled"
}

# Extract list of explicitly disabled hook names under git.hooks from a single YAML file.
_yaml_parse_disabled_git_hooks_from_file() {
  _yaml_parse_git_hooks_by_state "$1" "disabled"
}

# Enumerate configured hook names under git.hooks merged from rnex.yaml and .local.rnex.yaml.
# Respects .local.rnex.yaml priority: hooks explicitly disabled in .local.rnex.yaml are excluded.
# Results are strictly deduplicated and sorted deterministically.
yaml_get_git_hooks() {
  _yaml_resolve_files
  _local_hooks=""
  _local_disabled=""
  if [ -f "$_wly" ]; then
    _local_hooks="$(_yaml_parse_git_hooks_from_file "$_wly")"
    _local_disabled="$(_yaml_parse_disabled_git_hooks_from_file "$_wly")"
  fi
  _base_hooks=""
  if [ -f "$_wy" ]; then
    _base_hooks="$(_yaml_parse_git_hooks_from_file "$_wy")"
  fi
  {
    printf '%s\n' "$_local_hooks"
    if [ -n "$_base_hooks" ]; then
      printf '%s\n' "$_base_hooks" | while read -r _bh; do
        [ -n "$_bh" ] || continue
        if [ -n "$_local_disabled" ] && printf '%s\n' "$_local_disabled" | grep -qx "$_bh"; then
          continue
        fi
        printf '%s\n' "$_bh"
      done
    fi
  } | awk 'NF' | LC_ALL=C sort -u
}

# Extract command list for a specific hook under git.hooks.<hook_name> from a YAML file.
_yaml_git_hook_commands_from_file() {
  _yghc_f="$1"; _yghc_hook="$2"
  [ -f "$_yghc_f" ] || return 0
  awk -v target_hook="$_yghc_hook" "${_YAML_AWK_UNQUOTE}"'
    /^[ \t]*git:[ \t]*(#.*)?$/ { in_git=1; next }
    in_git && /^[^ \t#]/ { exit }
    !in_git { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_hook_cmds {
      if (indent > target_indent) {
        if (trimmed ~ /^enabled:[ \t]*false([ \t]|$|#)/) {
          exit
        }
        if (trimmed ~ /^-([ \t]|$)/) {
          item = unquote(substr(trimmed, 2))
          if (length(item) > 0) print item
        }
        next
      }
      exit
    }

    in_hooks && (indent <= hooks_indent) { in_hooks=0 }

    !in_hooks {
      if (trimmed ~ /^hooks:[ \t]*(#.*)?$/) {
        in_hooks = 1
        hooks_indent = indent
      }
      next
    }

    in_hooks {
      k = trimmed
      sub(/:.*/, "", k)
      k = unquote(k)
      if (k == target_hook && trimmed ~ /:[ \t]*/) {
        target_indent = indent
        val = trimmed
        sub(/^[^:]*:[ \t]*/, "", val)
        val = unquote(val)
        if (val == "false") {
          exit
        }
        if (val ~ /^(#.*)?$/) {
          in_hook_cmds = 1
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
        if (val != "true" && val !~ /^\{/) {
          item = unquote(val)
          if (length(item) > 0) print item
        }
        exit
      }
    }
  ' "$_yghc_f"
}

# Read command list for a specific hook under git.hooks.<hook_name>
# with .local.rnex.yaml override priority.
#
# @param $1 Hook name to query (e.g., pre-commit, post-merge).
# @returns Shell commands to execute for the given hook.
# @pure
yaml_get_git_hook_commands() {
  _hook_name="$1"
  _yaml_resolve_files
  if [ -f "$_wly" ]; then
    if _yaml_parse_disabled_git_hooks_from_file "$_wly" | grep -qx "$_hook_name"; then
      return 0
    fi
    if _yaml_parse_git_hooks_from_file "$_wly" | grep -qx "$_hook_name"; then
      _yaml_git_hook_commands_from_file "$_wly" "$_hook_name"
      return 0
    fi
  fi
  if [ -f "$_wy" ]; then
    _yaml_git_hook_commands_from_file "$_wy" "$_hook_name"
  fi
}

# ---- Lifecycle Hooks Configuration Operations (rnexHooks) ---------------

# ==============================================================================
# _yaml_to_camel
#
# Summary:
#   Converts a snake_case or kebab-case identifier to camelCase while preserving
#   identifiers that are already camelCase cleanly.
#
# @param $1 raw_ident Identifier string (e.g. "before_repo_add" or "beforeRepoAdd").
# @returns camelCase identifier on stdout.
# @pure
# ==============================================================================
_yaml_to_camel() {
  _ytc_raw="${1:-}"
  [ -n "$_ytc_raw" ] || return 0
  case "$_ytc_raw" in
    *[_-]*)
      printf '%s' "$_ytc_raw" | awk -F'[_-]+' '
        {
          out = $1
          for (i = 2; i <= NF; i++) {
            if ($i != "") {
              out = out toupper(substr($i, 1, 1)) substr($i, 2)
            }
          }
          print out
        }
      '
      ;;
    *)
      printf '%s' "$_ytc_raw"
      ;;
  esac
}

# Extract list of hook/event names defined under rnexHooks from a YAML file.
_yaml_rnex_hooks_list_from_file() {
  _yrhl_f="$1"
  [ -f "$_yrhl_f" ] || return 0
  awk '
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    # Detect top-level rnexHooks section header
    indent == 0 && trimmed ~ /^rnexHooks:[ \t]*(#.*)?$/ {
      in_hooks = 1
      hooks_indent = indent
      next
    }
    indent == 0 && trimmed ~ /^[a-zA-Z0-9_.-]+:/ {
      in_hooks = 0
      next
    }

    in_hooks && (indent <= hooks_indent) {
      in_hooks = 0
      next
    }

    in_hooks {
      if (trimmed ~ /^-([ \t]|$)/) next
      if (trimmed ~ /^[a-zA-Z0-9_.-]+:[ \t]*/) {
        k = trimmed
        sub(/:.*/, "", k)
        gsub(/^["\047]|["\047]$/, "", k)
        gsub(/[[:space:]]/, "", k)
        if (length(k) > 0) print k
      }
    }
  ' "$_yrhl_f" | awk '!seen[$0]++'
}

# Extract command list for a specific hook under rnexHooks.<event_name> from a YAML file.
_yaml_rnex_hook_commands_from_file() {
  _yrhc_f="$1"; _yrhc_hook="$2"
  [ -f "$_yrhc_f" ] || return 0
  awk -v target_hook="$_yrhc_hook" "${_YAML_AWK_UNQUOTE}"'
    BEGIN {
      in_hooks = 0
      in_hook_cmds = 0
    }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    in_hook_cmds {
      if (indent > target_indent || (indent == target_indent && trimmed ~ /^-([ \t]|$)/)) {
        if (trimmed ~ /^-([ \t]|$)/) {
          item = unquote(substr(trimmed, 2))
          if (length(item) > 0) print item
        }
        next
      }
      in_hook_cmds = 0
    }

    indent == 0 && trimmed ~ /^rnexHooks:[ \t]*(#.*)?$/ {
      in_hooks = 1
      hooks_indent = indent
      next
    }

    indent == 0 && trimmed ~ /^[a-zA-Z0-9_.-]+:/ {
      in_hooks = 0
      next
    }

    in_hooks && (indent <= hooks_indent) {
      in_hooks = 0
      next
    }

    in_hooks {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == target_hook && trimmed ~ /:[ \t]*/) {
        target_indent = indent
        val = trimmed
        sub(/^[^:]*:[ \t]*/, "", val)
        if (val ~ /^(#.*)?$/) {
          in_hook_cmds = 1
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
          next
        }
        item = unquote(val)
        if (length(item) > 0) print item
        next
      }
    }
  ' "$_yrhc_f"
}

# ==============================================================================
# rnex_yaml_get_rnex_hooks
#
# Summary:
#   Reads lifecycle hook commands for a specified stage from rnexHooks.<stage>
#   with strict .local.rnex.yaml override priority over rnex.yaml.
#   Adheres to strict opt-in execution: if the stage is not explicitly configured
#   or is set to an empty list / false, zero commands are returned.
#
# Architectural Layer:
#   Configuration Parser Layer (YAML Reader)
#
# Design Pattern:
#   Strategy / Information Expert (reads parsed YAML models deterministically)
#
# Arguments:
#   $1 - Optional workspace root directory (defaults to NEXUS_DIR or .).
#   $2 - Lifecycle stage name (e.g. "preSync", "postSync", "afterSync", "beforeSync").
#
# Returns:
#   Outputs newline-delimited hook command strings to stdout.
#   Returns 0 on success.
#
# Purity:
#   @pure (stateless file inspection, zero side effects)
# ==============================================================================
rnex_yaml_get_rnex_hooks() {
  _rygh_ws="${1:-${NEXUS_DIR:-${RNEX_ROOT:-.}}}"
  _rygh_stage="${2:-}"
  [ -n "$_rygh_stage" ] || return 0

  _rygh_stage_norm="$(_yaml_to_camel "$_rygh_stage")"

  # Stage aliases: preSync <-> beforeSync; postSync <-> afterSync
  _rygh_alias=""
  case "$_rygh_stage_norm" in
    preSync)    _rygh_alias="beforeSync" ;;
    beforeSync) _rygh_alias="preSync" ;;
    postSync)   _rygh_alias="afterSync" ;;
    afterSync)  _rygh_alias="postSync" ;;
  esac

  if [ -n "${1:-}" ]; then
    _rygh_wly="$_rygh_ws/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
    _rygh_wy="$_rygh_ws/${RNEX_CONFIG_FILE:-rnex.yaml}"
  else
    _rygh_wly="${WORKSPACE_LOCAL_YAML:-$_rygh_ws/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}}"
    _rygh_wy="${WORKSPACE_YAML:-$_rygh_ws/${RNEX_CONFIG_FILE:-rnex.yaml}}"
  fi

  # 1. Check .local.rnex.yaml (highest priority)
  if [ -f "$_rygh_wly" ]; then
    _local_stages="$(_yaml_rnex_hooks_list_from_file "$_rygh_wly")"
    if printf '%s\n' "$_local_stages" | grep -qx "$_rygh_stage_norm"; then
      _yaml_rnex_hook_commands_from_file "$_rygh_wly" "$_rygh_stage_norm"
      return 0
    elif [ -n "$_rygh_alias" ] && printf '%s\n' "$_local_stages" | grep -qx "$_rygh_alias"; then
      _yaml_rnex_hook_commands_from_file "$_rygh_wly" "$_rygh_alias"
      return 0
    fi
  fi

  # 2. Fall back to rnex.yaml
  if [ -f "$_rygh_wy" ]; then
    _base_stages="$(_yaml_rnex_hooks_list_from_file "$_rygh_wy")"
    if printf '%s\n' "$_base_stages" | grep -qx "$_rygh_stage_norm"; then
      _yaml_rnex_hook_commands_from_file "$_rygh_wy" "$_rygh_stage_norm"
      return 0
    elif [ -n "$_rygh_alias" ] && printf '%s\n' "$_base_stages" | grep -qx "$_rygh_alias"; then
      _yaml_rnex_hook_commands_from_file "$_rygh_wy" "$_rygh_alias"
      return 0
    fi
  fi

  return 0
}

# Backward compatibility wrapper for rnex_yaml_get_rnex_hooks
yaml_get_rnex_hook_commands() {
  rnex_yaml_get_rnex_hooks "${NEXUS_DIR:-${RNEX_ROOT:-.}}" "$1"
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

# ==============================================================================
# yaml_get_plugin_config
#
# Query a scalar plugin configuration setting (plugins.<plugin>.<key>) with
# strict two-level source-of-truth hierarchy and plugin defaults fallback:
#   1. .local.rnex.yaml ($NEXUS_LOCAL_CONFIG or $WORKSPACE_LOCAL_YAML)
#   2. rnex.yaml        ($NEXUS_CONFIG or $WORKSPACE_YAML)
#   3. <resolved_plugin_dir>/plugin.yaml (config_defaults.<key>)
#
# @param $1 plugin_name Target plugin name (e.g. "claude", "copilot").
# @param $2 key_name    Property key name (e.g. "path", "wiki_dir", "enabled").
# @returns 0 and value string if resolved; 1 if unset/not found.
# @pure Read-only configuration query.
# ==============================================================================
yaml_get_plugin_config() {
  _ygpc_plugin="$1"
  _ygpc_key="$2"
  _yaml_resolve_files

  _ygpc_local="${NEXUS_LOCAL_CONFIG:-$_wly}"
  _ygpc_main="${NEXUS_CONFIG:-$_wy}"

  # 1. Query .local.rnex.yaml first
  if [ -f "$_ygpc_local" ]; then
    _val="$(_yaml_plugin_get_from_file "$_ygpc_local" "$_ygpc_plugin" "$_ygpc_key")"
    if [ -n "$_val" ]; then
      printf '%s' "$_val"
      return 0
    fi
  fi

  # 2. Query rnex.yaml next
  if [ -f "$_ygpc_main" ]; then
    _val="$(_yaml_plugin_get_from_file "$_ygpc_main" "$_ygpc_plugin" "$_ygpc_key")"
    if [ -n "$_val" ]; then
      printf '%s' "$_val"
      return 0
    fi
  fi

  # 3. Fall back to resolved plugin directory plugin.yaml config_defaults
  # Do not recurse if querying "path"
  if [ "$_ygpc_key" != "path" ]; then
    _ygpc_pdir=""
    if command -v plugin_resolve_dir >/dev/null 2>&1; then
      _ygpc_pdir="$(plugin_resolve_dir "$_ygpc_plugin" 2>/dev/null || true)"
    elif command -v find_plugin_dir >/dev/null 2>&1; then
      _ygpc_pdir="$(find_plugin_dir "$_ygpc_plugin" 2>/dev/null || true)"
    fi

    if [ -n "$_ygpc_pdir" ] && [ -f "$_ygpc_pdir/plugin.yaml" ]; then
      _def_val="$(awk -v k="$_ygpc_key" '
        /^config_defaults:[ ]*$/ || /^config_defaults:[ ]*#/ { in_c=1; next }
        in_c && /^[^ #]/ { exit }
        in_c && ($0 ~ ("^[ ]*" k ":")) {
          line = $0
          sub(/^[ ]*[a-zA-Z0-9_.-]+:[ ]*/, "", line)
          sub(/[ ]*#.*/, "", line)
          sub(/^[ ]+/, "", line)
          sub(/[ \t\r]+$/, "", line)
          gsub(/^["\047]|["\047]$/, "", line)
          print line
          exit
        }
      ' "$_ygpc_pdir/plugin.yaml")"
      if [ -n "$_def_val" ]; then
        printf '%s' "$_def_val"
        return 0
      fi
    fi
  fi

  return 1
}

yaml_plugin_get() {
  yaml_get_plugin_config "$1" "$2"
}

# ==============================================================================
# _yaml_parse_plugin_list_from_file
#
# Parse a list-valued plugin configuration setting (plugins.<plugin>.<key>) from
# a single YAML file. Supports both inline flow sequences (e.g. `[a, "b"]`) and
# multi-line YAML block sequences (e.g. `sources:` followed by `- "a"`).
#
# Parsing Algorithm:
# 1. Locate the top-level `plugins:` block.
# 2. Locate `<plugin_name>:` nested under `plugins:`.
# 3. Locate `<key_name>:` nested under `<plugin_name>:`.
# 4. Inline Array Mode:
#    If the remainder of the `<key_name>:` line (after stripping inline `#`
#    comments) matches `[...]`, strip `[` and `]`, split on commas outside
#    quotes, trim leading/trailing whitespace, strip surrounding `"` or `'`,
#    strip leading `./`, and print one non-empty item per line.
# 5. Block Sequence Mode:
#    If the remainder of the `<key_name>:` line is empty, read subsequent lines
#    while their indentation is greater than `<plugin_name>:`'s indentation
#    (or equal to `<key_name>:`'s indentation for `- ` items). For each item
#    starting with `-`, strip `- `, strip inline comments, trim whitespace and
#    surrounding quotes (`"` or `'`), strip leading `./`, and output one item per line.
#    Stop at the next sibling key or lower-indented block.
#
# @param $1 file_path   Path to the YAML configuration file.
# @param $2 plugin_name Name of the target plugin under `plugins:`.
# @param $3 key_name    Name of the property under `<plugin_name>:`.
# @returns Newline-separated list of parsed string items.
# @pure Does not mutate filesystem or global environment.
# ==============================================================================
_yaml_parse_plugin_list_from_file() {
  _yppl_file="$1"
  _yppl_plugin="$2"
  _yppl_key="$3"
  [ -f "$_yppl_file" ] || return 0
  awk -v plugin="$_yppl_plugin" -v key="$_yppl_key" "${_YAML_AWK_LIST_LIB}"'
    # Step 1: Detect top-level plugins: block
    /^[ \t]*plugins:[ \t]*(#.*)?$/ {
      in_plugins = 1
      in_target_plugin = 0
      in_list = 0
      match($0, /^[ \t]*/)
      plugins_indent = RLENGTH
      next
    }

    # If leaving plugins section at same or lesser indentation, exit
    in_plugins && /^[^ \t#]/ {
      if (in_list) exit
      in_plugins = 0
      in_target_plugin = 0
      next
    }

    !in_plugins { next }

    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }

    # Step 2: In block list mode, process list items or detect termination
    in_list {
      # Skip empty lines or pure comment lines
      if (trimmed ~ /^([#]|$)/) next

      # Check if indentation has dropped to or below plugin level
      if (indent <= plugin_indent) exit

      # Check if this line is a list item starting with hyphen
      if (trimmed ~ /^-([ \t]|$)/) {
        line = trimmed
        sub(/^-+[ \t]*/, "", line)
        item = clean_item(line)
        if (length(item) > 0) print item
        next
      }

      # If indentation is greater than plugin_indent but does not start with "-",
      # it is a sibling key or non-list line: terminate block list mode
      exit
    }

    # Skip comments and blank lines outside list mode
    trimmed ~ /^([#]|$)/ { next }

    # Step 3: Handle target plugin boundary
    in_target_plugin && (indent <= plugin_indent) {
      in_target_plugin = 0
    }

    # Step 4: Search for target plugin key under plugins:
    !in_target_plugin {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_target_plugin = 1
        plugin_indent = indent
      }
      next
    }

    # Step 5: Inside target plugin, look for target key
    in_target_plugin && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k != key) next

      # Extract value after key:
      val = trimmed
      sub(/^[^:]*:[ \t]*/, "", val)

      # Check for inline flow array: [ ... ]
      if (val ~ /^\[/) {
        # Strip trailing comment after the closing bracket if present
        sub(/\][^\]]*$/, "]", val)
        if (val ~ /^\[.*\]$/) {
          inner = substr(val, 2, length(val) - 2)
          parse_inline_array(inner)
          exit
        }
      }

      # Strip inline comment and whitespace to check if empty
      v_clean = val
      sub(/[ \t]*#.*$/, "", v_clean)
      sub(/^[ \t]+/, "", v_clean)
      sub(/[ \t]+$/, "", v_clean)

      if (v_clean == "") {
        # Key line has no inline value -> enter block sequence mode
        in_list = 1
        key_indent = indent
        next
      } else {
        # Single scalar value on the same line
        item = clean_item(v_clean)
        if (length(item) > 0) print item
        exit
      }
    }
  ' "$_yppl_file"
}

# ==============================================================================
# yaml_get_plugin_list
#
# Query a list-valued plugin configuration setting (plugins.<plugin>.<key>) with
# strict two-level source-of-truth hierarchy and plugin defaults fallback:
#   1. .local.rnex.yaml ($NEXUS_LOCAL_CONFIG or $WORKSPACE_LOCAL_YAML)
#   2. rnex.yaml        ($NEXUS_CONFIG or $WORKSPACE_YAML)
#   3. plugins/<plugin_name>/plugin.yaml (config_defaults.<key>)
#
# Evaluates sources in priority order and emits the first non-empty list of items.
#
# @param $1 plugin_name Target plugin name (e.g. "copilot").
# @param $2 key_name    Property key name (e.g. "sources").
# @returns 0 and newline-delimited items if resolved; 1 if unset/not found.
# @pure Read-only configuration query.
# ==============================================================================
yaml_get_plugin_list() {
  _ygpl_plugin="$1"
  _ygpl_key="$2"
  _yaml_resolve_files

  _ygpl_local="${NEXUS_LOCAL_CONFIG:-$_wly}"
  _ygpl_main="${NEXUS_CONFIG:-$_wy}"

  # 1. Query $NEXUS_LOCAL_CONFIG (.local.rnex.yaml) first.
  if [ -f "$_ygpl_local" ]; then
    _ygpl_out="$(_yaml_parse_plugin_list_from_file "$_ygpl_local" "$_ygpl_plugin" "$_ygpl_key")"
    if [ -n "$_ygpl_out" ]; then
      printf '%s\n' "$_ygpl_out"
      return 0
    fi
  fi

  # 2. Otherwise query $NEXUS_CONFIG (rnex.yaml).
  if [ -f "$_ygpl_main" ]; then
    _ygpl_out="$(_yaml_parse_plugin_list_from_file "$_ygpl_main" "$_ygpl_plugin" "$_ygpl_key")"
    if [ -n "$_ygpl_out" ]; then
      printf '%s\n' "$_ygpl_out"
      return 0
    fi
  fi

  # 3. Otherwise fall back to resolved plugin.yaml under config_defaults:
  _ygpl_pdir=""
  if command -v plugin_resolve_dir >/dev/null 2>&1; then
    _ygpl_pdir="$(plugin_resolve_dir "$_ygpl_plugin" 2>/dev/null || true)"
  elif command -v find_plugin_dir >/dev/null 2>&1; then
    _ygpl_pdir="$(find_plugin_dir "$_ygpl_plugin" 2>/dev/null || true)"
  fi
  if [ -z "$_ygpl_pdir" ]; then
    for _cand in \
      "${NEXUS_DIR:-${RNEX_ROOT:-.}}/plugins/$_ygpl_plugin" \
      "${RNEX_ROOT:-}/plugins/$_ygpl_plugin" \
      "plugins/$_ygpl_plugin" \
      "${NEXUS_DIR:-${RNEX_ROOT:-.}}/.rnex/plugins/$_ygpl_plugin"; do
      if [ -f "$_cand/plugin.yaml" ]; then
        _ygpl_pdir="$_cand"
        break
      fi
    done
  fi

  if [ -n "$_ygpl_pdir" ] && [ -f "$_ygpl_pdir/plugin.yaml" ]; then
    _ygpl_out="$(_yaml_parse_plugin_default_from_manifest "$_ygpl_pdir/plugin.yaml" "$_ygpl_key")"
    if [ -n "$_ygpl_out" ]; then
      printf '%s\n' "$_ygpl_out"
      return 0
    fi
  fi

  return 1
}

# Get a list-valued plugin setting as newline-separated items.
# Precedence: .local.rnex.yaml > rnex.yaml > plugin.yaml config_defaults.
get_plugin_config_list() {
  yaml_get_plugin_list "$1" "$2" 2>/dev/null || true
}

# Audit a single YAML configuration file for deprecated top-level schema keys and
# malformed YAML hook list syntax that would otherwise be silently skipped.
#
# @param $1 file_path Path to rnex.yaml or .local.rnex.yaml.
# @returns Emits structured findings (<CODE>|<line>|<detail>) on stdout.
# @pure Read-only configuration inspection.
_yaml_audit_config_file() {
  _yacf_f="$1"
  [ -f "$_yacf_f" ] || return 0
  awk '
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }

    # Detect deprecated top-level keys removed in current camelCase schema
    indent == 0 && trimmed ~ /^repos_dir:[ \t]*/ {
      printf "LEGACY_REPOS_DIR|%d|repos_dir\n", NR
      in_rnex_hooks = 0; in_plugins = 0; plugin_entry_indent = -1; plugin_setting_indent = -1
      next
    }
    indent == 0 && trimmed ~ /^code_workspace:[ \t]*/ {
      printf "LEGACY_CODE_WORKSPACE|%d|code_workspace\n", NR
      in_rnex_hooks = 0; in_plugins = 0; plugin_entry_indent = -1; plugin_setting_indent = -1
      next
    }
    indent == 0 && trimmed ~ /^rnex_hooks:[ \t]*(#.*)?$/ {
      printf "LEGACY_RNEX_HOOKS|%d|%s\n", NR, trimmed
      in_rnex_hooks = 0; in_plugins = 0; plugin_entry_indent = -1; plugin_setting_indent = -1
      next
    }
    indent == 0 && trimmed ~ /^rnex-hooks:[ \t]*(#.*)?$/ {
      printf "LEGACY_RNEX_HOOKS_KEBAB|%d|%s\n", NR, trimmed
      in_rnex_hooks = 0; in_plugins = 0; plugin_entry_indent = -1; plugin_setting_indent = -1
      next
    }
    indent == 0 && trimmed ~ /^git_hooks:[ \t]*(#.*)?$/ {
      printf "LEGACY_GIT_HOOKS|%d|%s\n", NR, trimmed
      in_rnex_hooks = 0; in_plugins = 0; plugin_entry_indent = -1; plugin_setting_indent = -1
      next
    }
    indent == 0 && trimmed ~ /^sources:[ \t]*(#.*)?$/ {
      printf "LEGACY_ROOT_SOURCES|%d|%s\n", NR, trimmed
      in_rnex_hooks = 0; in_plugins = 0; plugin_entry_indent = -1; plugin_setting_indent = -1
      next
    }

    # Track plugins section generically (plugin-agnostic camelCase setting validation)
    indent == 0 && trimmed ~ /^plugins:[ \t]*(#.*)?$/ {
      in_plugins = 1
      plugins_child_indent = -1
      plugin_entry_indent = -1
      plugin_setting_indent = -1
      in_rnex_hooks = 0
      in_hooks_sub = 0
      next
    }

    # Track rnexHooks section for malformed YAML list items and deprecated stage keys
    indent == 0 && trimmed ~ /^rnexHooks:[ \t]*(#.*)?$/ {
      in_rnex_hooks = 1
      hooks_child_indent = -1
      in_hooks_sub = 0
      in_plugins = 0
      plugin_entry_indent = -1
      plugin_setting_indent = -1
      next
    }
    indent == 0 && trimmed ~ /^[a-zA-Z0-9_.-]+:/ {
      in_rnex_hooks = 0
      in_hooks_sub = 0
      in_plugins = 0
      plugin_entry_indent = -1
      plugin_setting_indent = -1
      next
    }

    in_plugins {
      if (plugins_child_indent < 0) plugins_child_indent = indent
      if (indent == plugins_child_indent && trimmed ~ /^[a-zA-Z0-9_.-]+:[ \t]*(\{\})?[ \t]*(#.*)?$/) {
        plugin_entry_indent = indent
        plugin_setting_indent = -1
        in_hooks_sub = 0
        next
      }
      if (plugin_entry_indent >= 0 && indent > plugin_entry_indent) {
        if (trimmed !~ /^-/ && plugin_setting_indent < 0) {
          plugin_setting_indent = indent
        }
        if (indent == plugin_setting_indent && trimmed !~ /^-/ && trimmed ~ /^[a-zA-Z0-9_.-]+:[ \t]*/) {
          k = trimmed
          sub(/:.*/, "", k)
          if (k ~ /_/) {
            printf "LEGACY_PLUGIN_KEY|%d|%s\n", NR, k
          }
        }
      }
    }

    # Track nested git.hooks or plugins.<p>.hooks sections for malformed list syntax
    trimmed ~ /^hooks:[ \t]*(#.*)?$/ && indent > 0 {
      in_hooks_sub = 1
      hooks_sub_indent = indent
      next
    }
    in_hooks_sub && indent <= hooks_sub_indent {
      in_hooks_sub = 0
    }

    in_rnex_hooks {
      if (trimmed !~ /^-/ && trimmed ~ /^[a-zA-Z0-9_.-]+:[ \t]*/) {
        if (hooks_child_indent < 0) hooks_child_indent = indent
        if (indent == hooks_child_indent) {
          k = trimmed
          sub(/:.*/, "", k)
          if (k ~ /[_-]/) {
            printf "LEGACY_RNEX_HOOK_STAGE|%d|%s\n", NR, k
          }
        }
      }
    }

    in_rnex_hooks || in_hooks_sub {
      # Flag inline sequence syntax immediately attached to hyphen (e.g. -"cmd" instead of - "cmd")
      if (trimmed ~ /^-[^ \t-]/) {
        printf "MALFORMED_HOOK_ITEM|%d|%s\n", NR, trimmed
        next
      }
      if (trimmed ~ /^[a-zA-Z0-9_.-]+:[ \t]*-[^ \t-]/) {
        printf "MALFORMED_HOOK_ITEM|%d|%s\n", NR, trimmed
        next
      }
    }
  ' "$_yacf_f"
}

# Validate merged workspace configuration files (rnex.yaml and .local.rnex.yaml)
# against deprecated keys and malformed YAML hook list syntax.
#
# @returns 0 if valid; 1 if any deprecated key or malformed syntax is detected.
# @sideEffects Writes diagnostic errors via log_err (stderr, always visible).
validate_workspace_config() {
  _yaml_resolve_files
  _vwc_err=0
  for _vwc_file in "${NEXUS_CONFIG:-$_wy}" "${NEXUS_LOCAL_CONFIG:-$_wly}"; do
    [ -f "$_vwc_file" ] || continue
    _vwc_name="$(basename "$_vwc_file")"
    _vwc_findings="$(_yaml_audit_config_file "$_vwc_file" 2>/dev/null || true)"
    [ -n "$_vwc_findings" ] || continue

    _vwc_rc_tmp=0
    while IFS='|' read -r _f_code _f_line _f_detail; do
      [ -n "$_f_code" ] || continue
      case "$_f_code" in
        LEGACY_REPOS_DIR)
          log_err "Deprecated configuration key 'repos_dir:' at $_vwc_name:$_f_line — rename it to 'reposDir:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_CODE_WORKSPACE)
          log_err "Deprecated configuration key 'code_workspace:' at $_vwc_name:$_f_line — rename it to 'codeWorkspace:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_RNEX_HOOKS)
          log_err "Deprecated configuration key 'rnex_hooks:' at $_vwc_name:$_f_line — rename it to 'rnexHooks:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_RNEX_HOOKS_KEBAB)
          log_err "Deprecated configuration key 'rnex-hooks:' at $_vwc_name:$_f_line — rename it to 'rnexHooks:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_RNEX_HOOK_STAGE)
          _f_camel="$(_yaml_to_camel "$_f_detail")"
          log_err "Deprecated hook event '$_f_detail:' under 'rnexHooks:' at $_vwc_name:$_f_line — rename it to '$_f_camel:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_PLUGIN_KEY)
          _f_camel="$(_yaml_to_camel "$_f_detail")"
          log_err "Deprecated plugin configuration setting '$_f_detail:' at $_vwc_name:$_f_line — rename it to '$_f_camel:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_GIT_HOOKS)
          log_err "Deprecated configuration key 'git_hooks:' at $_vwc_name:$_f_line — move Git hooks under 'git: hooks:'."
          _vwc_rc_tmp=1
          ;;
        LEGACY_ROOT_SOURCES)
          log_err "Deprecated top-level key 'sources:' at $_vwc_name:$_f_line — move 'sources:' under the owning plugin section (plugins.<name>.sources)."
          _vwc_rc_tmp=1
          ;;
        MALFORMED_HOOK_ITEM)
          log_err "Malformed YAML hook entry at $_vwc_name:$_f_line ('$_f_detail'): add a space after '-' (e.g. '- \"...\"')."
          _vwc_rc_tmp=1
          ;;
      esac
    done <<EOF_VWC
$_vwc_findings
EOF_VWC
    [ "$_vwc_rc_tmp" -eq 0 ] || _vwc_err=1
  done
  if rnex_get_code_workspace_enabled 2>/dev/null; then
    rnex_get_code_workspace_name >/dev/null 2>&1 || _vwc_err=1
    rnex_get_code_workspace_settings_json >/dev/null 2>&1 || _vwc_err=1
  fi
  return "$_vwc_err"
}

# Emit a plugin's config_defaults block from plugin.yaml, re-indented for insertion
# under plugins.<name> in rnex.yaml by shifting indentation +2 spaces and resolving
# workspace {reposDir} placeholders deterministically.
#
# @param $1 plugin_yaml Path to plugin.yaml manifest.
# @param $2 repos_dir   Optional relative repos directory (defaults to configured reposDir).
# @returns Re-indented YAML block lines on stdout.
# @pure Read-only manifest inspection.
plugin_config_default_lines() {
  _pcd_file="$1"
  _pcd_rdir="${2:-}"
  if [ -z "$_pcd_rdir" ] && command -v yaml_get_repos_dir >/dev/null 2>&1; then
    _pcd_rdir="$(yaml_get_repos_dir 2>/dev/null || true)"
  fi
  [ -n "$_pcd_rdir" ] || _pcd_rdir="repos"
  [ -f "$_pcd_file" ] || return 0
  awk -v rdir="$_pcd_rdir" '
    /^config_defaults:[ ]*$/ || /^config_defaults:[ ]*#/ { in_c=1; next }
    in_c && /^[^ #]/ { exit }
    in_c && /^[ ]*#/ { next }
    in_c && /^[ ]*$/ { next }
    in_c {
      line = $0
      gsub(/\{reposDir\}/, rdir, line)
      print "  " line
    }
  ' "$_pcd_file"
}

# Check whether plugins.<plugin>.hooks is explicitly defined in a YAML file.
_yaml_plugin_hooks_defined_in_file() {
  _yphd_f="$1"; _yphd_plugin="$2"
  [ -f "$_yphd_f" ] || return 1
  awk -v plugin="$_yphd_plugin" '
    BEGIN { found = 0 }
    /^[ \t]*plugins:[ \t]*(#.*)?$/ {
      in_plugins = 1
      in_plugin = 0
      match($0, /^[ \t]*/)
      plugins_indent = RLENGTH
      next
    }
    in_plugins && /^[^ \t#]/ { in_plugins = 0; in_plugin = 0; next }
    !in_plugins { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }
    in_plugin && (indent <= plugin_indent) { in_plugin = 0 }
    !in_plugin {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_plugin = 1
        plugin_indent = indent
      }
      next
    }
    in_plugin && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == "hooks" && trimmed ~ /:[ \t]*/) {
        found = 1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$_yphd_f"
}

# Extract list of hook event names under plugins.<plugin>.hooks from a YAML file.
_yaml_plugin_hooks_list_from_file() {
  _yphl_f="$1"; _yphl_plugin="$2"
  [ -f "$_yphl_f" ] || return 0
  awk -v plugin="$_yphl_plugin" '
    /^[ \t]*plugins:[ \t]*(#.*)?$/ {
      in_plugins = 1
      in_plugin = 0
      in_hooks = 0
      next
    }
    in_plugins && /^[^ \t#]/ { in_plugins = 0; in_plugin = 0; in_hooks = 0; next }
    !in_plugins { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }
    in_hooks && (indent <= hooks_indent) { in_hooks = 0 }
    in_plugin && (indent <= plugin_indent) { in_plugin = 0; in_hooks = 0 }
    !in_plugin {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_plugin = 1
        plugin_indent = indent
      }
      next
    }
    in_plugin && !in_hooks && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == "hooks" && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_hooks = 1
        hooks_indent = indent
        hook_item_indent = -1
      }
      next
    }
    in_hooks && (indent > hooks_indent) {
      if (trimmed ~ /^-([ \t]|$)/) next
      if (hook_item_indent == -1 || indent <= hook_item_indent) {
        hook_item_indent = indent
        k = trimmed
        sub(/:.*/, "", k)
        gsub(/^["\047]|["\047]$/, "", k)
        gsub(/[[:space:]]/, "", k)
        if (length(k) > 0) print k
      }
    }
  ' "$_yphl_f" | awk '!seen[$0]++'
}

# Extract command list for plugins.<plugin>.hooks.<event> from a YAML file.
_yaml_plugin_hook_commands_from_file() {
  _yphc_f="$1"; _yphc_plugin="$2"; _yphc_event="$3"
  [ -f "$_yphc_f" ] || return 0
  awk -v plugin="$_yphc_plugin" -v target_event="$_yphc_event" "${_YAML_AWK_UNQUOTE}"'
    /^[ \t]*plugins:[ \t]*(#.*)?$/ {
      in_plugins = 1
      in_plugin = 0
      in_hooks = 0
      in_cmds = 0
      next
    }
    in_plugins && /^[^ \t#]/ { in_plugins = 0; in_plugin = 0; in_hooks = 0; in_cmds = 0; next }
    !in_plugins { next }
    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
    }
    trimmed ~ /^([#]|$)/ { next }
    in_cmds {
      if (indent > event_indent || (indent == event_indent && trimmed ~ /^-([ \t]|$)/)) {
        if (trimmed ~ /^-([ \t]|$)/) {
          item = unquote(substr(trimmed, 2))
          if (length(item) > 0) print item
        }
        next
      }
      in_cmds = 0
    }
    in_hooks && (indent <= hooks_indent) { in_hooks = 0 }
    in_plugin && (indent <= plugin_indent) { in_plugin = 0; in_hooks = 0 }
    !in_plugin {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == plugin && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_plugin = 1
        plugin_indent = indent
      }
      next
    }
    in_plugin && !in_hooks && (indent > plugin_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k == "hooks" && trimmed ~ /:[ \t]*(#.*)?$/) {
        in_hooks = 1
        hooks_indent = indent
      }
      next
    }
    in_hooks && (indent > hooks_indent) {
      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if ((k == target_event || tolower(k) == tolower(target_event)) && trimmed ~ /:[ \t]*/) {
        event_indent = indent
        val = trimmed
        sub(/^[^:]*:[ \t]*/, "", val)
        if (val ~ /^(#.*)?$/) {
          in_cmds = 1
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
          next
        }
        item = unquote(val)
        if (length(item) > 0 && item != "false" && item != "none" && item != "off" && item != "0" && item != "{}") print item
        next
      }
    }
  ' "$_yphc_f"
}

# Resolve the winning workspace config file (.local.rnex.yaml > rnex.yaml) that
# explicitly defines active hooks for plugins.<plugin>.hooks.
# @param $1 Workspace root path (or empty for ambient globals).
# @param $2 Plugin identifier name.
# @returns Winning YAML file path on stdout and 0 if active; returns 1 if absent/disabled.
# @pure
_yaml_resolve_active_plugin_hooks_file() {
  _yraph_arg1="${1:-}"
  _yraph_ws="${_yraph_arg1:-${NEXUS_DIR:-${RNEX_ROOT:-.}}}"
  _yraph_plugin="${2:-}"
  [ -n "$_yraph_plugin" ] || return 1

  if [ -n "$_yraph_arg1" ]; then
    _yraph_wly="$_yraph_ws/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
    _yraph_wy="$_yraph_ws/${RNEX_CONFIG_FILE:-rnex.yaml}"
  else
    _yraph_wly="${WORKSPACE_LOCAL_YAML:-$_yraph_ws/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}}"
    _yraph_wy="${WORKSPACE_YAML:-$_yraph_ws/${RNEX_CONFIG_FILE:-rnex.yaml}}"
  fi

  for _yraph_cand in "$_yraph_wly" "$_yraph_wy"; do
    if [ -f "$_yraph_cand" ] && _yaml_plugin_hooks_defined_in_file "$_yraph_cand" "$_yraph_plugin"; then
      _scalar_h="$(_yaml_plugin_get_from_file "$_yraph_cand" "$_yraph_plugin" "hooks")"
      case "$_scalar_h" in
        false|off|none|0|"{}"|"[]") return 1 ;;
      esac
      printf '%s' "$_yraph_cand"
      return 0
    fi
  done
  return 1
}

# ==============================================================================
# rnex_yaml_get_plugin_hook_events
#
# Summary:
#   Extracts list of hook event names declared strictly under
#   plugins.<plugin_name>.hooks from rnex.yaml or .local.rnex.yaml.
#   Adheres to strict opt-in execution: NEVER merges or falls back to
#   plugin.yaml manifest defaults.
# ==============================================================================
rnex_yaml_get_plugin_hook_events() {
  _rygpe_plugin="${2:-}"
  [ -n "$_rygpe_plugin" ] || return 0
  _rygpe_file="$(_yaml_resolve_active_plugin_hooks_file "${1:-}" "$_rygpe_plugin")" || return 0
  _yaml_plugin_hooks_list_from_file "$_rygpe_file" "$_rygpe_plugin"
}

# Backward compatibility alias for rnex_yaml_get_plugin_hook_events
yaml_list_plugin_hooks() {
  rnex_yaml_get_plugin_hook_events "${NEXUS_DIR:-${RNEX_ROOT:-.}}" "$1"
}

# ==============================================================================
# rnex_yaml_get_plugin_hook_commands
#
# Summary:
#   Extracts command list for plugins.<plugin_name>.hooks.<event_name> strictly
#   from rnex.yaml or .local.rnex.yaml.
#   Adheres to strict opt-in execution: NEVER merges or falls back to
#   plugin.yaml manifest defaults.
# ==============================================================================
rnex_yaml_get_plugin_hook_commands() {
  _rygpc_plugin="${2:-}"
  _rygpc_event="${3:-}"
  [ -n "$_rygpc_plugin" ] && [ -n "$_rygpc_event" ] || return 0
  _rygpc_file="$(_yaml_resolve_active_plugin_hooks_file "${1:-}" "$_rygpc_plugin")" || return 0
  _yaml_plugin_hook_commands_from_file "$_rygpc_file" "$_rygpc_plugin" "$_rygpc_event"
}

# Backward compatibility alias for rnex_yaml_get_plugin_hook_commands
yaml_get_plugin_hook_commands() {
  _ygphc_p="$1"; _ygphc_ev="$2"
  rnex_yaml_get_plugin_hook_commands "${NEXUS_DIR:-${RNEX_ROOT:-.}}" "$_ygphc_p" "$_ygphc_ev"
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

_yaml_plugin_set_in_file() {
  _yaml_section_set "$1" "plugins" "$2" "$3" "$4"
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

# Get configured target branch for a repo (from .local.rnex.yaml or rnex.yaml)
yaml_get_repo_branch() {
  yaml_get "$1" "branch"
}

# ---- Deterministic Merged-Config Queries -----------------------------------
# Precedence: .local.rnex.yaml > rnex.yaml > defaults. Output ordering is
# byte-wise (LC_ALL=C) so results are identical across BSD/GNU platforms.

# List all repository keys from both config files, deduplicated and sorted.
yaml_list_all_repos_sorted() {
  yaml_list_repos | LC_ALL=C sort -u
}

# Resolve repos.<repo>.<field> (local > project), falling back to <default>.
yaml_get_merged_repo_field() {
  _ygmr_val="$(yaml_get "$1" "$2")"
  [ -n "$_ygmr_val" ] || _ygmr_val="${3:-}"
  printf '%s' "$_ygmr_val"
}

# ==============================================================================
# _yaml_parse_plugin_default_from_manifest
#
# Extract a list or scalar default setting under `config_defaults.<key>` from a
# plugin manifest file (`plugin.yaml`). Supports both inline flow sequences
# (`[a, "b"]`) and multi-line block sequences (`- "a"`).
#
# @param $1 manifest_file Path to plugin.yaml manifest.
# @param $2 key_name      Target property key under `config_defaults:`.
# @returns Newline-separated list of items.
# @pure Does not mutate filesystem or global environment.
# ==============================================================================
_yaml_parse_plugin_default_from_manifest() {
  _ypdm_f="$1"
  _ypdm_key="$2"
  [ -f "$_ypdm_f" ] || return 0
  awk -v key="$_ypdm_key" "${_YAML_AWK_LIST_LIB}"'
    /^config_defaults:[ \t]*(#.*)?$/ { in_defaults = 1; next }
    in_defaults && /^[^ \t#]/ { exit }
    !in_defaults { next }

    in_list {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
      if (trimmed ~ /^([#]|$)/) next
      if (trimmed ~ /^-([ \t]|$)/) {
        line = trimmed
        sub(/^-+[ \t]*/, "", line)
        item = clean_item(line)
        if (length(item) > 0) print item
        next
      }
      exit
    }

    {
      match($0, /^[ \t]*/)
      indent = RLENGTH
      trimmed = substr($0, indent + 1)
      if (trimmed ~ /^([#]|$)/) next

      k = trimmed
      sub(/:.*/, "", k)
      gsub(/^["\047]|["\047]$/, "", k)
      gsub(/[[:space:]]/, "", k)
      if (k != key) next

      val = trimmed
      sub(/^[^:]*:[ \t]*/, "", val)

      if (val ~ /^\[/) {
        sub(/\][^\]]*$/, "]", val)
        if (val ~ /^\[.*\]$/) {
          inner = substr(val, 2, length(val) - 2)
          parse_inline_array(inner)
          exit
        }
      }

      v_clean = val
      sub(/[ \t]*#.*$/, "", v_clean)
      sub(/^[ \t]+/, "", v_clean)
      sub(/[ \t]+$/, "", v_clean)

      if (v_clean == "") {
        in_list = 1
        next
      } else {
        item = clean_item(v_clean)
        if (length(item) > 0) print item
        exit
      }
    }
  ' "$_ypdm_f"
}

# Add a new repository entry under 'repos:' in the main workspace configuration (rnex.yaml).
yaml_add_repo() {
  _name="$1"; _url="$2"; _enabled="${3:-true}"; _readonly="${4:-false}"; _branch="${5:-}"
  if ! grep -q '^repos:' "$WORKSPACE_YAML" 2>/dev/null; then
    printf '\nrepos:\n' >> "$WORKSPACE_YAML"
  fi
  _tmp="$(mktemp)"
  _YAR_NAME="$_name" _YAR_URL="$_url" _YAR_EN="$_enabled" _YAR_RO="$_readonly" _YAR_BR="$_branch" awk '
    BEGIN {
      name = ENVIRON["_YAR_NAME"]
      url = ENVIRON["_YAR_URL"]
      en = ENVIRON["_YAR_EN"]
      ro = ENVIRON["_YAR_RO"]
      br = ENVIRON["_YAR_BR"]
    }
    !added && /^repos:/ {
      print
      printf "  %s:\n    url: %s\n", name, url
      if (en == "false") printf "    enabled: false\n"
      if (ro == "true") printf "    readonly: true\n"
      if (br != "") printf "    branch: %s\n", br
      added = 1
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

# Set or insert a top-level scalar property in a specific YAML file atomically.
# Updates ONLY the first matching column-0 key in-place; if absent, inserts it
# after any YAML document start marker ('---') and leading header comments.
# Avoids rewriting the file when bytes are unchanged.
#
# @param $1 file   Target YAML file path.
# @param $2 key    Top-level property key name (alphanumeric, '_', '.', '-').
# @param $3 value  Single-line scalar value string.
# @returns 0 on success; 1 if file missing/unwritable or arguments invalid.
# @sideEffects Atomically updates target YAML file via mktemp + mv when changed.
_yaml_set_top_level_in_file() {
  _file="$1"; _key="$2"; _val="$3"
  [ -f "$_file" ] && [ -w "$_file" ] || return 1

  # Reject unsafe key names (regex/awk metacharacters) or multi-line values
  case "$_key" in
    ""|*[!a-zA-Z0-9_.-]*) return 1 ;;
  esac
  case "$_val" in
    *"
"*) return 1 ;;
  esac

  _tmp="$(mktemp)" || return 1
  _yst_ok=0
  if awk -v pat="^${_key}[ \t]*:" 'BEGIN { f = 0 } $0 ~ pat { f = 1; exit } END { exit !f }' "$_file" 2>/dev/null; then
    if _YST_VAL="$_val" awk -v key="$_key" '
      BEGIN { val = ENVIRON["_YST_VAL"]; updated = 0 }
      !updated && $0 ~ ("^" key "[ \t]*:") {
        print key ": " val
        updated = 1
        next
      }
      { print }
    ' "$_file" > "$_tmp"; then
      _yst_ok=1
    fi
  else
    if _YST_VAL="$_val" awk -v key="$_key" '
      BEGIN { val = ENVIRON["_YST_VAL"]; inserted = 0 }
      !inserted && $0 !~ /^[ \t]*(#.*)?$/ && $0 !~ /^---([ \t]*#.*)?$/ {
        print key ": " val
        print ""
        inserted = 1
      }
      { print }
      END {
        if (!inserted) {
          print key ": " val
        }
      }
    ' "$_file" > "$_tmp"; then
      _yst_ok=1
    fi
  fi

  if [ "$_yst_ok" -eq 1 ]; then
    if ! cmp -s "$_file" "$_tmp"; then
      mv "$_tmp" "$_file"
    else
      rm -f "$_tmp"
    fi
    return 0
  fi

  rm -f "$_tmp"
  return 1
}

# Set or insert a top-level scalar property in team workspace config (rnex.yaml).
# @param $1 key    Top-level scalar key name.
# @param $2 value  Single-line scalar value string.
# @returns 0 on success; non-zero on failure.
yaml_set_top_level() {
  _yaml_resolve_files
  _yaml_set_top_level_in_file "${WORKSPACE_YAML:-$_wy}" "$1" "$2"
}

# ==============================================================================
# Structured `codeWorkspace` Resolver & Pure POSIX YAML-to-JSON Serializer
# Architectural Layer: Configuration Contract & Serialization Module
# Pattern: Pure Query Facade + AST Pretty-Printer (POSIX /bin/sh + POSIX awk)
# Responsibility:
#   Centralize `codeWorkspace` constants, OWASP A03 filename validation,
#   nested key presence detection, POSIX YAML-to-JSON serialization, and pure
#   two-level config getters (.local.rnex.yaml > rnex.yaml > defaults).
# ==============================================================================

RNEX_CODE_WORKSPACE_EXT=".code-workspace"
RNEX_DEFAULT_CODE_WORKSPACE_SETTINGS_JSON='{
  "search.exclude": {
    "**/node_modules": true,
    "**/.git": true,
    "**/.rnex": true
  }
}'

# ------------------------------------------------------------------------------
# Validate a candidate `codeWorkspace.name` against a strict OWASP A03 ASCII
# allowlist (^[A-Za-z0-9][A-Za-z0-9._-]*$, rejecting '..', trailing '.', '/',
# '\', whitespace, newlines, and control characters).
# @param $1 - Candidate workspace name string.
# @returns 0 if valid; 1 if missing, empty, or invalid (zero output).
# @pure
# ------------------------------------------------------------------------------
rnex_validate_workspace_name() {
  [ $# -ge 1 ] && [ -n "$1" ] || return 1
  case "$1" in
    [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*) return 1 ;;
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) return 1 ;;
    *..*|*.) return 1 ;;
  esac
  return 0
}

# ------------------------------------------------------------------------------
# Normalize a validated workspace name to '<name>.code-workspace' without
# duplicating RNEX_CODE_WORKSPACE_EXT if already present.
# @param $1 - Candidate workspace name.
# @returns Normalized filename on stdout (exit 0), or nothing (exit 1) if invalid.
# @pure
# ------------------------------------------------------------------------------
rnex_normalize_workspace_filename() {
  [ $# -ge 1 ] && rnex_validate_workspace_name "$1" || return 1
  case "$1" in
    *"$RNEX_CODE_WORKSPACE_EXT") printf '%s' "$1" ;;
    *) printf '%s%s' "$1" "$RNEX_CODE_WORKSPACE_EXT" ;;
  esac
}

# Shared POSIX awk lexical helpers (quote-aware comment stripping, mapping
# colon lookup, scalar unquoting, and sequence indicator detection).
# shellcheck disable=SC2016
_RNEX_YAML_AWK_LEX='
function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}

function strip_comment(line,    len, i, c, prev, sq, dq) {
  sub(/\r$/, "", line)
  len = length(line); sq = 0; dq = 0; prev = ""
  for (i = 1; i <= len; i++) {
    c = substr(line, i, 1)
    if (sq) {
      if (c == "\047") {
        if (substr(line, i + 1, 1) == "\047") { i++; prev = c; continue }
        sq = 0
      }
    } else if (dq) {
      if (c == "\\") { i++; prev = ""; continue }
      if (c == "\"") dq = 0
    } else {
      if (c == "\047") sq = 1
      else if (c == "\"") dq = 1
      else if (c == "#" && (i == 1 || prev == " " || prev == "\t")) {
        line = substr(line, 1, i - 1)
        sub(/[ \t]+$/, "", line)
        return line
      }
    }
    prev = c
  }
  sub(/[ \t]+$/, "", line)
  return line
}

# Locate top-level mapping colon outside quotes/brackets.
# Returns >0 (1-based index), 0 (none), or -1 (unterminated quote).
function find_colon(s,    len, i, c, nxt, sq, dq, bd, kd, cq) {
  len = length(s); sq = 0; dq = 0; bd = 0; kd = 0; cq = 0
  for (i = 1; i <= len; i++) {
    c = substr(s, i, 1)
    if (sq) {
      if (c == "\047") {
        if (substr(s, i + 1, 1) == "\047") { i++; continue }
        sq = 0; if (bd == 0 && kd == 0) cq = 1
      }
    } else if (dq) {
      if (c == "\\") { i++; continue }
      if (c == "\"") { dq = 0; if (bd == 0 && kd == 0) cq = 1 }
    } else {
      if (c == "\047") { sq = 1; cq = 0 }
      else if (c == "\"") { dq = 1; cq = 0 }
      else if (c == "{") { bd++; cq = 0 }
      else if (c == "}") { bd--; cq = 0 }
      else if (c == "[") { kd++; cq = 0 }
      else if (c == "]") { kd--; cq = 0 }
      else if (c == ":" && bd == 0 && kd == 0) {
        nxt = substr(s, i + 1, 1)
        if (nxt == "" || nxt == " " || nxt == "\t" || cq) return i
        cq = 0
      } else if (c != " " && c != "\t") { cq = 0 }
    }
  }
  return (sq || dq) ? -1 : 0
}

function unquote_val(raw,    s, len, i, c, esc, out) {
  s = trim(raw); len = length(s)
  if (len >= 2 && substr(s, 1, 1) == "\"" && substr(s, len, 1) == "\"") {
    out = ""
    for (i = 2; i < len; i++) {
      c = substr(s, i, 1)
      if (c == "\\" && i < len - 1) {
        i++; esc = substr(s, i, 1)
        if (esc == "n") out = out "\n"
        else if (esc == "t") out = out "\t"
        else if (esc == "r") out = out "\r"
        else out = out esc
      } else out = out c
    }
    return out
  }
  if (len >= 2 && substr(s, 1, 1) == "\047" && substr(s, len, 1) == "\047") {
    out = ""
    for (i = 2; i < len; i++) {
      c = substr(s, i, 1)
      if (c == "\047" && substr(s, i + 1, 1) == "\047" && i < len - 1) { i++; out = out "\047" }
      else out = out c
    }
    return out
  }
  return s
}

function is_seq_line(t,    c2) {
  if (t == "-") return 1
  if (substr(t, 1, 1) != "-") return 0
  c2 = substr(t, 2, 1)
  return (c2 == " " || c2 == "\t") ? 1 : 0
}
'

# Shared nested key query/extraction engine for rnex_yaml_has_nested_key ("has")
# and rnex_yaml_extract_nested_block ("extract"). Matches direct children of
# top-level <parent_key> (block or inline `{...}` form) while ignoring grandchildren.
# @param $1 mode ("has"|"extract"), $2 file, $3 parent_key, $4 child_key
# @returns 0 if declared; 1 otherwise.
# @pure
_rnex_yaml_nested() {
  [ $# -ge 4 ] && [ -f "$2" ] && [ -n "$3" ] && [ -n "$4" ] || return 1
  # shellcheck disable=SC2016
  LC_ALL=C _RYN_MODE="$1" _RYN_PARENT="$3" _RYN_CHILD="$4" \
    awk "${_RNEX_YAML_AWK_LEX}"'
    function scan_inline_parent(s,    len, i, c, sq, dq, d, st, seg, cp, rk, rv) {
      s = trim(s); len = length(s)
      if (len < 2 || substr(s, 1, 1) != "{" || substr(s, len, 1) != "}") return 0
      s = substr(s, 2, len - 2); len = length(s)
      sq = 0; dq = 0; d = 0; st = 1
      for (i = 1; i <= len + 1; i++) {
        c = (i <= len) ? substr(s, i, 1) : ","
        if (i <= len) {
          if (sq) { if (c == "\047") { if (substr(s, i + 1, 1) == "\047") i++; else sq = 0 } continue }
          if (dq) { if (c == "\\") i++; else if (c == "\"") dq = 0; continue }
          if (c == "\047") { sq = 1; continue }
          if (c == "\"") { dq = 1; continue }
          if (c == "{" || c == "[") { d++; continue }
          if (c == "}" || c == "]") { d--; continue }
        }
        if (c == "," && d == 0) {
          seg = trim(substr(s, st, i - st)); st = i + 1
          cp = find_colon(seg)
          if (cp > 0 && unquote_val(substr(seg, 1, cp - 1)) == CHILD) {
            rv = trim(substr(seg, cp + 1))
            if (MODE == "extract" && rv != "") print rv
            return 1
          }
        }
      }
      return 0
    }
    BEGIN {
      MODE = ENVIRON["_RYN_MODE"]; PARENT = ENVIRON["_RYN_PARENT"]; CHILD = ENVIRON["_RYN_CHILD"]
      found = 0; in_p = 0; child_col = -1; in_c = 0; c_ind = -1; c_inline = 0
    }
    {
      cl = strip_comment($0)
      if (cl == "") next
      match(cl, /^[ \t]*/); ind = RLENGTH; ws = substr(cl, 1, ind); tr = substr(cl, ind + 1)
      if (tr == "") next

      if (in_c) {
        if (ind == 0 && (tr == "---" || tr == "...")) exit 0
        if (ws ~ /\t/ || ind > c_ind || (!c_inline && ind == c_ind && is_seq_line(tr))) {
          print cl; next
        }
        exit 0
      }

      if (ind == 0 && (tr == "---" || tr == "...")) { in_p = 0; next }

      if (in_p) {
        if (ind == 0) {
          in_p = 0
        } else {
          if (child_col == -1) child_col = ind
          if (ind == child_col) {
            cp = find_colon(tr)
            if (cp > 0 && unquote_val(substr(tr, 1, cp - 1)) == CHILD) {
              found = 1
              if (MODE == "has") exit 0
              in_c = 1; c_ind = ind
              cv = trim(substr(tr, cp + 1))
              if (cv != "") { c_inline = 1; print cv } else c_inline = 0
            }
          }
          next
        }
      }

      if (ind == 0) {
        cp = find_colon(tr)
        if (cp > 0 && unquote_val(substr(tr, 1, cp - 1)) == PARENT) {
          pv = trim(substr(tr, cp + 1))
          if (pv == "") { in_p = 1; child_col = -1 }
          else if (substr(pv, 1, 1) == "{" && scan_inline_parent(pv)) { found = 1; exit 0 }
        }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$2"
}

# Check whether <child_key> is explicitly declared under top-level <parent_key>.
# @param $1 file, $2 parent_key, $3 child_key
# @returns 0 if declared (including `{}`), 1 if absent or file missing.
# @pure
rnex_yaml_has_nested_key() {
  _rnex_yaml_nested "has" "${1:-}" "${2:-}" "${3:-}"
}

# Extract raw indented YAML subtree (or inline value) under <parent_key>.<child_key>.
# @param $1 file, $2 parent_key, $3 child_key
# @returns Extracted YAML lines on stdout (exit 0), or exit 1 if absent.
# @pure
rnex_yaml_extract_nested_block() {
  _rnex_yaml_nested "extract" "${1:-}" "${2:-}" "${3:-}"
}

# Pure POSIX awk YAML-to-JSON AST serializer backing rnex_yaml_block_to_json.
# Supports nested block mappings, block/indentless/compact sequences, inline
# flow `{}`/`[]`/`{...}`/`[...]`, typed scalars, and strict RFC 8259 escaping.
# shellcheck disable=SC2016
_RNEX_YAML_AWK_TO_JSON='
function fail(ln, msg) { ERR = 1; EMSG = sprintf("YAML error (line %d): %s", ln, msg); exit 1 }
function mk_node(t, v,    id) { id = ++NC; NT[id] = t; NV[id] = v; ML[id] = 0; SL[id] = 0; return id }
function map_put(mid, k, cid,    idx, n) {
  if ((mid SUBSEP k) in MKI) { MC[mid, MKI[mid, k]] = cid; return }
  n = ++ML[mid]; MK[mid, n] = k; MC[mid, n] = cid; MKI[mid, k] = n
}
function seq_push(sid, cid) { SC[sid, ++SL[sid]] = cid }
function j_esc(c) { return (c in ESC) ? ESC[c] : c }
function j_plain(s,    i, n, o) { n = length(s); o = ""; for (i = 1; i <= n; i++) o = o j_esc(substr(s, i, 1)); return DQ o DQ }

function j_dquote(raw, ln,    n, inn, m, i, c, e, h, o) {
  n = length(raw)
  if (n < 2 || substr(raw, 1, 1) != DQ || substr(raw, n, 1) != DQ) fail(ln, "unterminated double-quoted string")
  inn = substr(raw, 2, n - 2); m = length(inn); o = ""
  for (i = 1; i <= m; i++) {
    c = substr(inn, i, 1)
    if (c == BS) {
      if (i == m) fail(ln, "unterminated escape")
      i++; e = substr(inn, i, 1)
      if (e == DQ) o = o BS DQ
      else if (e == BS) o = o BS BS
      else if (e == "/") o = o "/"
      else if (e == "b" || e == "f" || e == "n" || e == "r" || e == "t") o = o BS e
      else if (e == "0") o = o "\\u0000"
      else if (e == " ") o = o " "
      else if (e == "u") {
        h = substr(inn, i + 1, 4)
        if (length(h) != 4 || h !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) fail(ln, "invalid \\uXXXX escape")
        o = o "\\u" h; i += 4
      } else fail(ln, "unsupported escape " BS e)
    } else if (c == DQ) fail(ln, "unexpected quote in double-quoted string")
    else o = o j_esc(c)
  }
  return DQ o DQ
}

function j_squote(raw, ln,    n, inn, m, i, c, o) {
  n = length(raw)
  if (n < 2 || substr(raw, 1, 1) != SQ || substr(raw, n, 1) != SQ) fail(ln, "unterminated single-quoted string")
  inn = substr(raw, 2, n - 2); m = length(inn); o = ""
  for (i = 1; i <= m; i++) {
    c = substr(inn, i, 1)
    if (c == SQ) {
      if (i < m && substr(inn, i + 1, 1) == SQ) { i++; o = o SQ }
      else fail(ln, "unexpected quote in single-quoted string")
    } else o = o j_esc(c)
  }
  return DQ o DQ
}

function parse_key(raw, ln,    k, fc) {
  k = trim(raw); if (k == "") fail(ln, "empty key")
  fc = substr(k, 1, 1)
  if (fc == DQ) return j_dquote(k, ln)
  if (fc == SQ) return j_squote(k, ln)
  if (k == "<<" || fc == "&" || fc == "*" || fc == "!" || fc == "{" || fc == "[" || fc == "}" || fc == "]") {
    fail(ln, "unsupported YAML key: " k)
  }
  return j_plain(k)
}

function parse_scalar(raw, ln,    v, fc) {
  v = trim(raw); fc = substr(v, 1, 1)
  if (fc == DQ) return j_dquote(v, ln)
  if (fc == SQ) return j_squote(v, ln)
  if (fc == "&" || fc == "*" || fc == "!") fail(ln, "unsupported YAML anchor/alias/tag: " v)
  if (v ~ /^[|>]([-+0-9]*)?([ \t].*)?$/) fail(ln, "unsupported multiline block scalar: " v)
  if (fc == "}" || fc == "]") fail(ln, "unexpected closing delimiter: " fc)
  if (v == "true" || v == "True" || v == "TRUE") return "true"
  if (v == "false" || v == "False" || v == "FALSE") return "false"
  if (v == "null" || v == "Null" || v == "NULL" || v == "~") return "null"
  if (v ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) return v
  if (find_colon(v) != 0) fail(ln, "invalid nested colon or unclosed quote: " v)
  return j_plain(v)
}

function split_flow(inn, out_arr, ln,    n, i, c, sq, dq, d, st, cnt, exp_stk) {
  n = length(inn); sq = 0; dq = 0; d = 0; st = 1; cnt = 0
  for (i = 1; i <= n; i++) {
    c = substr(inn, i, 1)
    if (sq) { if (c == SQ) { if (substr(inn, i + 1, 1) == SQ) i++; else sq = 0 } continue }
    if (dq) { if (c == BS) i++; else if (c == DQ) dq = 0; continue }
    if (c == SQ) sq = 1
    else if (c == DQ) dq = 1
    else if (c == "{") exp_stk[++d] = "}"
    else if (c == "[") exp_stk[++d] = "]"
    else if (c == "}" || c == "]") {
      if (d <= 0 || exp_stk[d] != c) fail(ln, "mismatched brackets/braces in flow collection")
      d--
    } else if (c == "," && d == 0) {
      out_arr[++cnt] = substr(inn, st, i - st); st = i + 1
    }
  }
  if (sq || dq || d != 0) fail(ln, "unclosed quote or flow collection")
  out_arr[++cnt] = substr(inn, st, n - st + 1)
  return cnt
}

function parse_flow(expr, ln,    n, i, c, sq, dq, d, fc, inn, id, cnt, seg, cp, rk, rv, estk, items) {
  expr = trim(expr); n = length(expr); fc = substr(expr, 1, 1)
  sq = 0; dq = 0; d = 0
  for (i = 1; i <= n; i++) {
    c = substr(expr, i, 1)
    if (sq) { if (c == SQ) { if (substr(expr, i + 1, 1) == SQ) i++; else sq = 0 } continue }
    if (dq) { if (c == BS) i++; else if (c == DQ) dq = 0; continue }
    if (c == SQ) sq = 1
    else if (c == DQ) dq = 1
    else if (c == "{") estk[++d] = "}"
    else if (c == "[") estk[++d] = "]"
    else if (c == "}" || c == "]") {
      if (d <= 0 || estk[d] != c) fail(ln, "mismatched brackets/braces")
      d--; if (d == 0 && i < n) fail(ln, "unexpected trailing content after flow collection")
    }
  }
  if (sq || dq || d != 0) fail(ln, "unclosed flow collection or quote")

  inn = trim(substr(expr, 2, n - 2))
  if (fc == "[") {
    id = mk_node("seq", "")
    if (inn == "") return id
    cnt = split_flow(inn, items, ln)
    for (i = 1; i <= cnt; i++) {
      seg = trim(items[i])
      if (seg == "") { if (i == cnt && cnt > 1) continue; fail(ln, "empty array element") }
      c = substr(seg, 1, 1)
      seq_push(id, (c == "{" || c == "[") ? parse_flow(seg, ln) : mk_node("scalar", parse_scalar(seg, ln)))
    }
    return id
  }
  id = mk_node("map", "")
  if (inn == "") return id
  cnt = split_flow(inn, items, ln)
  for (i = 1; i <= cnt; i++) {
    seg = trim(items[i])
    if (seg == "") { if (i == cnt && cnt > 1) continue; fail(ln, "empty map entry") }
    cp = find_colon(seg); if (cp <= 0) fail(ln, "expected key: value in flow map")
    rk = parse_key(substr(seg, 1, cp - 1), ln); rv = trim(substr(seg, cp + 1))
    if (rv == "") map_put(id, rk, mk_node("scalar", "null"))
    else {
      c = substr(rv, 1, 1)
      map_put(id, rk, (c == "{" || c == "[") ? parse_flow(rv, ln) : mk_node("scalar", parse_scalar(rv, ln)))
    }
  }
  return id
}

function push_stk(nid, col, pcol, indless) {
  SP++; SN[SP] = nid; SI[SP] = col; SPI[SP] = pcol; SIL[SP] = indless
}

function add_map_entry(mid, mcol, entry, ln,    cp, kj, rv, fc, pid) {
  cp = find_colon(entry)
  if (cp < 0) fail(ln, "unterminated quote in mapping")
  if (cp == 0) fail(ln, "expected key: value mapping")
  kj = parse_key(substr(entry, 1, cp - 1), ln)
  rv = trim(substr(entry, cp + 1))
  if (rv == "") { pid = mk_node("pending", ""); map_put(mid, kj, pid); push_stk(pid, -1, mcol, 0); return }
  fc = substr(rv, 1, 1)
  if (fc == "{" || fc == "[") map_put(mid, kj, parse_flow(rv, ln))
  else map_put(mid, kj, mk_node("scalar", parse_scalar(rv, ln)))
}

function render(id, depth,    t, n, i, pad, cpad, o) {
  t = NT[id]
  if (t == "scalar") return NV[id]
  if (t == "pending") return "null"
  pad = ""; for (i = 1; i <= depth; i++) pad = pad "  "
  cpad = pad "  "
  if (t == "map") {
    n = ML[id]; if (n == 0) return "{}"
    o = "{\n"
    for (i = 1; i <= n; i++) o = o cpad MK[id, i] ": " render(MC[id, i], depth + 1) (i < n ? "," : "") "\n"
    return o pad "}"
  }
  n = SL[id]; if (n == 0) return "[]"
  o = "[\n"
  for (i = 1; i <= n; i++) o = o cpad render(SC[id, i], depth + 1) (i < n ? "," : "") "\n"
  return o pad "]"
}

BEGIN {
  SQ = "\047"; DQ = "\""; BS = "\\"
  for (_i = 1; _i <= 31; _i++) {
    _c = sprintf("%c", _i)
    if (_i == 8) ESC[_c] = BS "b"
    else if (_i == 9) ESC[_c] = BS "t"
    else if (_i == 10) ESC[_c] = BS "n"
    else if (_i == 12) ESC[_c] = BS "f"
    else if (_i == 13) ESC[_c] = BS "r"
    else ESC[_c] = sprintf("\\u%04x", _i)
  }
  ESC[DQ] = BS DQ; ESC[BS] = BS BS
  ERR = 0; NC = 0; ROOT = 0; LOCKED = 0; SP = 0
}

{
  cl = strip_comment($0); if (cl == "") next
  match(cl, /^[ \t]*/); ind = RLENGTH; ws = substr(cl, 1, ind); tr = substr(cl, ind + 1)
  if (tr == "") next
  if (ws ~ /\t/) fail(NR, "tab characters are not allowed in indentation")
  if (LOCKED) fail(NR, "unexpected content after flow root")

  if (SP == 0) {
    fc = substr(tr, 1, 1)
    if (fc == "{" || fc == "[") { ROOT = parse_flow(tr, NR); LOCKED = 1; next }
    if (is_seq_line(tr)) { ROOT = mk_node("seq", ""); push_stk(ROOT, ind, -1, 0) }
    else if (find_colon(tr) > 0) { ROOT = mk_node("map", ""); push_stk(ROOT, ind, -1, 0) }
    else fail(NR, "expected YAML mapping, sequence, or flow object")
  }

  # Resolve pending container from prior bare `key:` or `-`
  while (SP >= 1 && NT[SN[SP]] == "pending") {
    pn = SN[SP]; pi = SPI[SP]
    if (ind > pi) { NT[pn] = is_seq_line(tr) ? "seq" : "map"; SI[SP] = ind; break }
    if (ind == pi && is_seq_line(tr) && SP > 1 && NT[SN[SP - 1]] == "map") {
      NT[pn] = "seq"; SI[SP] = ind; SIL[SP] = 1; break
    }
    NT[pn] = "scalar"; NV[pn] = "null"; SP--
  }

  # Unwind indentation stack on de-indent
  while (SP > 1) {
    if (ind < SI[SP] || (ind == SI[SP] && SIL[SP] == 1 && !is_seq_line(tr))) SP--
    else break
  }

  if (ind != SI[SP]) fail(NR, sprintf("inconsistent indentation (got %d, expected %d)", ind, SI[SP]))
  cid = SN[SP]

  if (NT[cid] == "map") {
    if (is_seq_line(tr)) fail(NR, "unexpected sequence item inside mapping")
    add_map_entry(cid, ind, tr, NR); next
  }

  if (!is_seq_line(tr)) fail(NR, "expected sequence item (-)")
  rest = substr(tr, 2); match(rest, /^[ \t]*/); dws = RLENGTH; item = substr(rest, dws + 1)
  if (item == "") { pn = mk_node("pending", ""); seq_push(cid, pn); push_stk(pn, -1, ind, 0); next }
  fc = substr(item, 1, 1)
  if (fc == "{" || fc == "[") { seq_push(cid, parse_flow(item, NR)); next }
  icp = find_colon(item)
  if (icp < 0) fail(NR, "unterminated quote in sequence item")
  if (icp > 0) {
    if (substr(rest, 1, dws) ~ /\t/) fail(NR, "tab characters are not allowed after -")
    im = mk_node("map", ""); seq_push(cid, im)
    push_stk(im, ind + 1 + dws, ind, 0); add_map_entry(im, ind + 1 + dws, item, NR); next
  }
  seq_push(cid, mk_node("scalar", parse_scalar(item, NR)))
}

END {
  if (ERR) { print EMSG; exit 1 }
  if (ROOT == 0) { print "{}"; exit 0 }
  print render(ROOT, 0)
}
'

# ------------------------------------------------------------------------------
# Serialize a YAML block from stdin into 2-space-indented strict RFC 8259 JSON.
# @param stdin - Extracted YAML block.
# @returns Formatted JSON on stdout (exit 0), or error on stderr (exit 1).
# @pure
# ------------------------------------------------------------------------------
rnex_yaml_block_to_json() {
  (
    set +e
    _out="$(LC_ALL=C awk "${_RNEX_YAML_AWK_LEX}${_RNEX_YAML_AWK_TO_JSON}")"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
      printf '%b[✗]%b %s\n' "${_R:-}" "${_NC:-}" "${_out:-Invalid YAML block}" >&2
      exit 1
    fi
    printf '%s\n' "$_out"
  )
}

# Internal helper: resolve (_cw_local, _cw_base) config paths for optional <root>.
_rnex_cw_config_files() {
  if [ -n "${1:-}" ]; then
    if [ -n "${NEXUS_DIR:-}" ] && [ "$1" = "$NEXUS_DIR" ] && [ -n "${WORKSPACE_YAML:-}" ]; then
      _cw_base="$WORKSPACE_YAML"
      _cw_local="${WORKSPACE_LOCAL_YAML:-$1/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}}"
    else
      _cw_base="$1/${RNEX_CONFIG_FILE:-rnex.yaml}"
      [ -f "$_cw_base" ] || { [ -f "$1/.rnex.yaml" ] && _cw_base="$1/.rnex.yaml"; }
      _cw_local="$1/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
    fi
  else
    _yaml_resolve_files
    _cw_base="$_wy"
    _cw_local="$_wly"
  fi
}

# Internal helper: inspect top-level `codeWorkspace:` in $1 for legacy scalar form.
# Returns 0 and prints unquoted scalar if legacy scalar; returns 1 if absent or object.
_rnex_cw_legacy_scalar_in_file() {
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  # shellcheck disable=SC2016
  LC_ALL=C awk "${_RNEX_YAML_AWK_LEX}"'
    BEGIN { kind = "absent"; raw = "" }
    {
      cl = strip_comment($0); if (cl == "") next
      match(cl, /^[ \t]*/); if (RLENGTH != 0) next
      if (cl == "---" || cl == "...") next
      cp = find_colon(cl)
      if (cp > 0 && unquote_val(substr(cl, 1, cp - 1)) == "codeWorkspace") {
        pv = trim(substr(cl, cp + 1))
        if (pv == "" || substr(pv, 1, 1) == "{") { kind = "object"; raw = "" }
        else { kind = "scalar"; raw = pv }
      }
    }
    END { if (kind == "scalar") { print unquote_val(raw); exit 0 } exit 1 }
  ' "$1"
}

# Internal helper: extract and unquote a single-line scalar under codeWorkspace.<child>.
# Returns 0 and prints plain string if valid single-line scalar; 1 if non-scalar/malformed.
_rnex_cw_nested_scalar() {
  _raw="$(rnex_yaml_extract_nested_block "$1" "codeWorkspace" "$2")" || return 1
  # shellcheck disable=SC2016
  printf '%s\n' "$_raw" | LC_ALL=C awk "${_RNEX_YAML_AWK_LEX}"'
    BEGIN { n = 0; v = "" }
    { s = trim($0); if (s == "") next; n++; if (n > 1) exit 1; v = s }
    END {
      if (n == 0) exit 0
      fc = substr(v, 1, 1); len = length(v)
      if (fc == "{" || fc == "[" || fc == "&" || fc == "*" || fc == "!") exit 1
      if (fc == "\"" && (len < 2 || substr(v, len, 1) != "\"")) exit 1
      if (fc == "\047" && (len < 2 || substr(v, len, 1) != "\047")) exit 1
      printf "%s", unquote_val(v)
    }
  '
}

# ------------------------------------------------------------------------------
# Return 0 if either active config file (.local.rnex.yaml or rnex.yaml) uses
# deprecated scalar `codeWorkspace: true|false|<name>` syntax; 1 otherwise.
# @param $1 - Optional workspace root directory.
# @returns 0 if legacy scalar syntax is present; 1 otherwise (zero output).
# @pure
# ------------------------------------------------------------------------------
rnex_is_legacy_code_workspace() {
  (
    _rnex_cw_config_files "${1:-}"
    if _rnex_cw_legacy_scalar_in_file "$_cw_local" >/dev/null 2>&1; then exit 0; fi
    if _rnex_cw_legacy_scalar_in_file "$_cw_base" >/dev/null 2>&1; then exit 0; fi
    exit 1
  )
}

# ------------------------------------------------------------------------------
# Pure predicate returning 0 if `codeWorkspace` is enabled, 1 if disabled.
# Precedence: .local.rnex.yaml (`codeWorkspace.enabled` > legacy scalar) >
#             rnex.yaml (`codeWorkspace.enabled` > legacy scalar) > false.
# @param $1 - Optional workspace root directory.
# @returns 0 if enabled, 1 if disabled (zero stdout/stderr side effects).
# @pure
# ------------------------------------------------------------------------------
rnex_get_code_workspace_enabled() {
  (
    set +e
    _rnex_cw_config_files "${1:-}"
    for _f in "$_cw_local" "$_cw_base"; do
      [ -f "$_f" ] || continue
      if rnex_yaml_has_nested_key "$_f" "codeWorkspace" "enabled"; then
        _v="$(_rnex_cw_nested_scalar "$_f" "enabled")" || exit 1
        is_truthy "$_v"; exit $?
      fi
      if _lv="$(_rnex_cw_legacy_scalar_in_file "$_f")"; then
        _lc="$(printf '%s' "$_lv" | tr '[:upper:]' '[:lower:]')"
        case "$_lc" in
          false|no|0|off|none|disabled|null|"~"|"" ) exit 1 ;;
          *) exit 0 ;;
        esac
      fi
    done
    exit 1
  )
}

# ------------------------------------------------------------------------------
# Resolve `codeWorkspace.name` across .local.rnex.yaml > rnex.yaml (with legacy
# non-boolean filename scalar compatibility). Outputs empty string (exit 0) if
# omitted; validates via rnex_validate_workspace_name and fails fast (exit 1)
# on invalid names.
# @param $1 - Optional workspace root directory.
# @returns Validated name (or empty string) on stdout (exit 0); exit 1 if invalid.
# @pure
# ------------------------------------------------------------------------------
rnex_get_code_workspace_name() {
  (
    set +e
    _rnex_cw_config_files "${1:-}"
    for _f in "$_cw_local" "$_cw_base"; do
      [ -f "$_f" ] || continue
      if rnex_yaml_has_nested_key "$_f" "codeWorkspace" "name"; then
        _nm="$(_rnex_cw_nested_scalar "$_f" "name")"
        _rc=$?
        if [ "$_rc" -ne 0 ] || ! rnex_validate_workspace_name "$_nm"; then
          printf '%b[✗]%b Invalid codeWorkspace.name in %s: must match ^[A-Za-z0-9][A-Za-z0-9._-]*$ without path separators or "..".\n' \
            "${_R:-}" "${_NC:-}" "$(basename "$_f")" >&2
          exit 1
        fi
        printf '%s' "$_nm"
        exit 0
      fi
    done

    # Backward compatibility for legacy scalar filename (`codeWorkspace: custom.code-workspace`)
    for _f in "$_cw_local" "$_cw_base"; do
      [ -f "$_f" ] || continue
      if _lv="$(_rnex_cw_legacy_scalar_in_file "$_f")"; then
        _lc="$(printf '%s' "$_lv" | tr '[:upper:]' '[:lower:]')"
        case "$_lc" in
          true|false|yes|no|1|0|on|off|none|enabled|disabled|null|"~"|"" ) exit 0 ;;
          *)
            if ! rnex_validate_workspace_name "$_lv"; then
              printf '%b[✗]%b Invalid codeWorkspace filename in %s.\n' "${_R:-}" "${_NC:-}" "$(basename "$_f")" >&2
              exit 1
            fi
            printf '%s' "$_lv"
            exit 0
            ;;
        esac
      fi
    done
    exit 0
  )
}

# ------------------------------------------------------------------------------
# Resolve `codeWorkspace.settings` JSON with atomic block replacement (no merge):
#   .local.rnex.yaml `settings` > rnex.yaml `settings` > built-in defaults.
# @param $1 - Optional workspace root directory.
# @returns Valid RFC 8259 JSON object on stdout (exit 0); exit 1 on YAML error.
# @pure
# ------------------------------------------------------------------------------
rnex_get_code_workspace_settings_json() {
  (
    set +e
    _rnex_cw_config_files "${1:-}"
    for _f in "$_cw_local" "$_cw_base"; do
      [ -f "$_f" ] || continue
      if rnex_yaml_has_nested_key "$_f" "codeWorkspace" "settings"; then
        _blk="$(rnex_yaml_extract_nested_block "$_f" "codeWorkspace" "settings")" || exit 1
        printf '%s\n' "$_blk" | rnex_yaml_block_to_json
        exit $?
      fi
    done
    printf '%s\n' "$RNEX_DEFAULT_CODE_WORKSPACE_SETTINGS_JSON"
  )
}
