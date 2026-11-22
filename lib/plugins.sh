#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/plugins.sh — Plugin Engine (discovery, metadata, and scoped synchronization)
# ============================================================================

# ============================================================================
# plugin_resolve_dir
#
# Summary:
#   Resolve the directory for a given plugin name according to the resolution
#   priority order:
#     1. Explicit per-plugin path override (`plugins.<name>.path` in
#        .local.rnex.yaml > rnex.yaml). Normalizes trailing `/plugin.yaml`
#        to its parent directory.
#     2. Built-in embedded plugin in `$RNEX_PLUGINS_DIR/<name>`.
#     3. Standard candidate plugin directory search.
#
# Arguments:
#   $1 - Plugin name (e.g. "copilot", "claude", "custom-plugin")
#
# Returns:
#   Outputs the resolved directory path to stdout; returns 0 on success,
#   or 1 if the plugin directory cannot be resolved.
#
# Purity:
#   @pure (stateless filesystem inspection based on configuration)
# ============================================================================
plugin_resolve_dir() {
  _prd_name="$1"
  [ -n "$_prd_name" ] || return 1

  # OWASP A03 / Path Traversal Guard: plugin name must strictly match allowlist
  case "$_prd_name" in
    *[!a-zA-Z0-9._-]*|"") return 1 ;;
    .|..) return 1 ;;
  esac

  _ws_root="${NEXUS_DIR:-${RNEX_ROOT:-.}}"

  # Priority 1: Explicit per-plugin path override (.local.rnex.yaml > rnex.yaml)
  if command -v yaml_get_plugin_config >/dev/null 2>&1; then
    _prd_path="$(yaml_get_plugin_config "$_prd_name" "path" 2>/dev/null || true)"
    if [ -n "$_prd_path" ]; then
      # Normalize trailing /plugin.yaml to parent directory
      case "$_prd_path" in
        */plugin.yaml) _prd_path="${_prd_path%/plugin.yaml}" ;;
        plugin.yaml)   _prd_path="." ;;
      esac
      # Strip trailing slashes
      while [ "$_prd_path" != "${_prd_path%/}" ] && [ -n "${_prd_path%/}" ]; do
        _prd_path="${_prd_path%/}"
      done
      # If relative path, prefix with workspace root if needed
      case "$_prd_path" in
        /*) _prd_full="$_prd_path" ;;
        *)
          if [ -n "$_ws_root" ] && [ "$_ws_root" != "." ]; then
            _prd_full="$_ws_root/${_prd_path#./}"
          else
            _prd_full="$_prd_path"
          fi
          ;;
      esac
      _prd_resolved="$(resolve_path "$_prd_full" 2>/dev/null || true)"
      if [ -n "$_prd_resolved" ] && [ -d "$_prd_resolved" ] && [ -f "$_prd_resolved/plugin.yaml" ]; then
        printf '%s' "$_prd_resolved"
        return 0
      fi
    fi
  fi

  # Priority 2: Built-in embedded plugin in $RNEX_PLUGINS_DIR/<plugin_name>
  if [ -n "${RNEX_PLUGINS_DIR:-}" ] && [ -d "$RNEX_PLUGINS_DIR/$_prd_name" ] && [ -f "$RNEX_PLUGINS_DIR/$_prd_name/plugin.yaml" ]; then
    resolve_path "$RNEX_PLUGINS_DIR/$_prd_name" 2>/dev/null || printf '%s' "$RNEX_PLUGINS_DIR/$_prd_name"
    return 0
  fi

  # Priority 3: Candidate plugin locations fallback
  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in \
    "${RNEX_ROOT:-}/plugins/$_prd_name" \
    "${RNEX_PLUGINS_DIR:-}/$_prd_name" \
    "${PLUGINS_DIR:-}/$_prd_name" \
    "$SCRIPT_LOCATION/plugins/$_prd_name" \
    "$_sdir/plugins/$_prd_name" \
    "$NEXUS_DIR/plugins/$_prd_name" \
    "$NEXUS_DIR/.rnex/plugins/$_prd_name"; do
    [ -n "$_cand" ] || continue
    if [ -f "$_cand/plugin.yaml" ]; then
      resolve_path "$_cand" 2>/dev/null || printf '%s' "$_cand"
      return 0
    fi
  done

  return 1
}

# Search all candidate plugin directories and locate a plugin by name containing plugin.yaml.
find_plugin_dir() {
  _query="$1"
  [ -n "$_query" ] || return 1

  # OWASP A03 / Path Traversal Guard: plugin query must strictly match allowlist
  case "$_query" in
    *[!a-zA-Z0-9._-]*|"") return 1 ;;
    .|..) return 1 ;;
  esac
  if command -v plugin_resolve_dir >/dev/null 2>&1; then
    _res="$(plugin_resolve_dir "$_query" 2>/dev/null || true)"
    if [ -n "$_res" ]; then
      printf '%s' "$_res"
      return 0
    fi
  fi

  _sdir="$(dirname "$SCRIPT_LOCATION")"
  for _cand in \
    "${RNEX_ROOT:-}/plugins/$_query" \
    "${RNEX_PLUGINS_DIR:-}/$_query" \
    "${PLUGINS_DIR:-}/$_query" \
    "$SCRIPT_LOCATION/plugins/$_query" \
    "$_sdir/plugins/$_query" \
    "$NEXUS_DIR/plugins/$_query" \
    "$NEXUS_DIR/.rnex/plugins/$_query"; do
    [ -n "$_cand" ] || continue
    if [ -f "$_cand/plugin.yaml" ]; then
      printf '%s' "$_cand"
      return 0
    fi
  done
  return 1
}

# ==============================================================================
# rnex_plugins_list_ordered_active
#
# Summary:
#   Returns the deterministic sequence of active (enabled) plugin names
#   strictly ordered by their declaration position in the merged workspace
#   configuration (rnex.yaml declaration order, followed by any local-only
#   additions in .local.rnex.yaml). Plugins marked with enabled: false (or
#   falsy equivalents) in .local.rnex.yaml or rnex.yaml are filtered out.
#   Each plugin name is strictly validated against a POSIX safe identifier
#   allowlist to prevent path-traversal attacks (OWASP A03).
#
# Architectural Layer:
#   Plugin Discovery & Query Engine
#
# Design Pattern:
#   Information Expert (GRASP)
#
# Arguments:
#   $1 - (Optional) Workspace root directory path (defaults to ambient NEXUS_DIR)
#
# Returns:
#   Outputs active plugin names to stdout, one per line. Exit code 0.
#
# Security:
#   OWASP A03 (Injection / Path Traversal): Enforces POSIX allowlist ^[a-zA-Z0-9._-]+$
#   and explicitly rejects navigation tokens ('.', '..').
#
# Purity:
#   @pure (stateless query of resolved configuration files)
# ==============================================================================
rnex_plugins_list_ordered_active() {
  _rplo_ws="${1:-}"
  _rplo_old_nd="${NEXUS_DIR:-}"
  _rplo_old_wy="${WORKSPACE_YAML:-}"
  _rplo_old_wly="${WORKSPACE_LOCAL_YAML:-}"

  # Set scoped configuration variables if explicit workspace root is passed
  if [ -n "$_rplo_ws" ]; then
    NEXUS_DIR="$_rplo_ws"
    WORKSPACE_YAML="$_rplo_ws/${RNEX_CONFIG_FILE:-rnex.yaml}"
    WORKSPACE_LOCAL_YAML="$_rplo_ws/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  fi

  if command -v yaml_list_plugins >/dev/null 2>&1; then
    yaml_list_plugins 2>/dev/null | while IFS= read -r _rplo_p || [ -n "$_rplo_p" ]; do
      [ -n "$_rplo_p" ] || continue

      # OWASP A03 / Path Traversal Guard: plugin name must strictly match ^[a-zA-Z0-9._-]+$
      case "$_rplo_p" in
        *[!a-zA-Z0-9._-]*|"")
          continue
          ;;
        .|..)
          continue
          ;;
      esac

      # Filter out plugins that are disabled in merged configuration (.local.rnex.yaml > rnex.yaml)
      if command -v yaml_plugin_enabled >/dev/null 2>&1; then
        yaml_plugin_enabled "$_rplo_p" 2>/dev/null || continue
      fi

      printf '%s\n' "$_rplo_p"
    done
  fi

  # Restore ambient configuration variables if overridden
  if [ -n "$_rplo_ws" ]; then
    NEXUS_DIR="$_rplo_old_nd"
    WORKSPACE_YAML="$_rplo_old_wy"
    WORKSPACE_LOCAL_YAML="$_rplo_old_wly"
  fi
}

# ============================================================================
# plugin_list_available
#
# Summary:
#   Discovers and lists all unique available plugin directories according to
#   the resolution hierarchy:
#     1. Path-mapped external plugins declared via `plugins.<name>.path` in
#        .local.rnex.yaml or rnex.yaml.
#     2. Built-in embedded plugins shipped with rnex ($RNEX_PLUGINS_DIR/*).
#
# Arguments:
#   None
#
# Returns:
#   Outputs resolved directory paths, one per line.
#
# Purity:
#   @pure (stateless filesystem and configuration inspection)
# ============================================================================
plugin_list_available() {
  _pla_seen=""

  # 1. Path-mapped plugins explicitly configured in YAML (.local.rnex.yaml > rnex.yaml)
  if command -v yaml_list_plugins >/dev/null 2>&1; then
    for _pname in $(yaml_list_plugins 2>/dev/null || true); do
      [ -n "$_pname" ] || continue
      _pdir="$(plugin_resolve_dir "$_pname" 2>/dev/null || true)"
      if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
        case " $_pla_seen " in
          *" $_pname "*) ;;
          *)
            _pla_seen="$_pla_seen $_pname"
            printf '%s\n' "$_pdir"
            ;;
        esac
      fi
    done
  fi

  # 2. Built-in embedded plugins ($RNEX_PLUGINS_DIR/*) and standard candidates
  for _parent in \
    "${RNEX_PLUGINS_DIR:-}" \
    "${PLUGINS_DIR:-}" \
    "${RNEX_ROOT:-}/plugins" \
    "$SCRIPT_LOCATION/plugins" \
    "$(dirname "$SCRIPT_LOCATION")/plugins" \
    "$NEXUS_DIR/plugins"; do
    [ -n "$_parent" ] || continue
    if [ -d "$_parent" ]; then
      for _sub in "$_parent"/*; do
        if [ -d "$_sub" ] && [ -f "$_sub/plugin.yaml" ]; then
          _pname="$(plugin_get_field "$_sub" "name" 2>/dev/null || true)"
          [ -n "$_pname" ] || _pname="$(basename "$_sub")"
          case " $_pla_seen " in
            *" $_pname "*) ;;
            *)
              _pla_seen="$_pla_seen $_pname"
              printf '%s\n' "$_sub"
              ;;
          esac
        fi
      done
    fi
  done
}

# Scan and list all unique plugin directories across workspace and built-in plugin locations.
list_all_available_plugin_dirs() {
  plugin_list_available
}

# Extract a top-level scalar field (e.g. name, version, description) from plugin.yaml.
plugin_get_field() {
  _pdir="$1"; _fld="$2"
  [ -f "$_pdir/plugin.yaml" ] || return 1
  awk -v fld="$_fld" '
    $0 ~ ("^" fld ":") {
      sub("^" fld ":[ ]*", "");
      sub(/[ ]*#.*/, "");
      print
    }
  ' "$_pdir/plugin.yaml"
}

# ============================================================================
# plugin_get_version
#
# Summary:
#   Retrieve the effective version of a plugin. Built-in embedded plugins
#   located in $RNEX_PLUGINS_DIR/<name> have version parity with rnex and
#   always report $RNEX_VERSION. External or custom plugins report the
#   'version' field from their plugin.yaml, defaulting to 'custom' if unset.
#
# Arguments:
#   $1 - Plugin name (e.g. "copilot", "claude")
#   $2 - (Optional) Pre-resolved directory path of the plugin
#
# Returns:
#   Outputs the version string to stdout.
#
# Purity:
#   @pure (stateless inspection of plugin metadata, no side effects)
# ============================================================================
plugin_get_version() {
  _pgv_name="$1"
  _pgv_dir="${2:-}"
  [ -n "$_pgv_name" ] || return 1

  # If directory was not provided, attempt resolution
  if [ -z "$_pgv_dir" ]; then
    if command -v plugin_resolve_dir >/dev/null 2>&1; then
      _pgv_dir="$(plugin_resolve_dir "$_pgv_name" 2>/dev/null || true)"
    fi
    [ -n "$_pgv_dir" ] || _pgv_dir="$(find_plugin_dir "$_pgv_name" 2>/dev/null || true)"
  fi

  # Resolve canonical path for the built-in plugin directory
  _tk_plugin_dir=""
  if [ -n "$RNEX_PLUGINS_DIR" ] && [ -d "$RNEX_PLUGINS_DIR/$_pgv_name" ]; then
    _tk_plugin_dir="$(resolve_path "$RNEX_PLUGINS_DIR/$_pgv_name" 2>/dev/null || true)"
  fi

  # Resolve canonical path for the candidate plugin directory
  _res_plugin_dir=""
  if [ -n "$_pgv_dir" ]; then
    _res_plugin_dir="$(resolve_path "$_pgv_dir" 2>/dev/null || true)"
  fi

  # Case 1: The resolved directory directly matches the built-in plugin
  if [ -n "$_tk_plugin_dir" ] && [ -n "$_res_plugin_dir" ] && [ "$_tk_plugin_dir" = "$_res_plugin_dir" ]; then
    printf '%s' "${RNEX_VERSION:-0.8.16}"
    return 0
  fi

  # Case 2: The directory is a scoped copy inside .rnex/plugins/<name>
  # originating from a built-in embedded plugin
  case "$_res_plugin_dir" in
    */.rnex/plugins/$_pgv_name)
      if [ -n "$_tk_plugin_dir" ] && [ -d "$_tk_plugin_dir" ]; then
        printf '%s' "${RNEX_VERSION:-0.8.16}"
        return 0
      fi
      ;;
  esac

  # Case 3: External or custom plugin — extract version from plugin.yaml
  _ver=""
  if [ -n "$_pgv_dir" ] && [ -f "$_pgv_dir/plugin.yaml" ]; then
    _ver="$(plugin_get_field "$_pgv_dir" "version" 2>/dev/null || true)"
  fi

  if [ -n "$_ver" ]; then
    printf '%s' "$_ver"
  else
    printf 'custom'
  fi
}

# Resolve target user skill directory for a provider plugin from plugin.yaml.
plugin_get_skill_dir() {
  _pgs_name="$1"
  _pgs_pdir="${2:-}"
  [ -n "$_pgs_pdir" ] || _pgs_pdir="$(plugin_resolve_dir "$_pgs_name" 2>/dev/null || true)"
  [ -n "$_pgs_pdir" ] || _pgs_pdir="$(find_plugin_dir "$_pgs_name" 2>/dev/null || true)"
  _pgs_dir=""
  if [ -n "$_pgs_pdir" ]; then
    _pgs_dir="$(plugin_get_field "$_pgs_pdir" "skill_dir" 2>/dev/null || true)"
  fi
  printf '%s' "$_pgs_dir"
}

# Parse declared template source-to-destination mappings from plugin.yaml.
plugin_list_templates() {
  _pdir="$1"
  [ -f "$_pdir/plugin.yaml" ] || return 0
  awk '
    /^templates:/ { t=1; next }
    t && /^[^ #]/ { exit }
    t && /^[ ]*-[ ]*/ {
      sub(/^[ ]*-[ ]*/, "");
      sub(/[ ]*#.*/, "");
      gsub(/["\047]/, "");
      if (length($0) > 0) print $0
    }
  ' "$_pdir/plugin.yaml"
}

# Parse declared instruction files from plugin.yaml.
plugin_list_instructions() {
  _pdir="$1"
  [ -f "$_pdir/plugin.yaml" ] || return 0
  awk '
    /^instructions:/ { t=1; next }
    t && /^[^ #]/ { exit }
    t && /^[ ]*-[ ]*/ {
      sub(/^[ ]*-[ ]*/, "");
      sub(/[ ]*#.*/, "");
      if (length($0) > 0) print $0
    }
  ' "$_pdir/plugin.yaml"
}

# Escape \, &, and | characters in a string for safe use as a POSIX sed replacement.
#
# @param $1 raw_value Unescaped replacement value.
# @returns Escaped string on stdout.
# @pure
_sed_escape_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Extract direct scalar configuration key names declared under config_defaults: in
# a plugin manifest, skipping structured sequence/map keys (sources, hooks).
#
# @param $1 manifest_file Path to plugin.yaml.
# @returns Newline-separated key names on stdout.
# @pure
_plugin_config_default_keys() {
  _pcdk_file="$1"
  [ -f "$_pcdk_file" ] || return 0
  awk '
    /^config_defaults:[ ]*(#.*)?$/ { in_c=1; def_indent=-1; next }
    in_c && /^[^ #]/ { exit }
    in_c && /^[ ]*(#|$)/ { next }
    in_c {
      match($0, /^[ ]*/)
      ind = RLENGTH
      if (def_indent == -1) def_indent = ind
      if (ind == def_indent && $0 ~ /^[ ]*[a-zA-Z0-9_.-]+:[ ]*/) {
        k = $0
        sub(/^[ ]*/, "", k)
        sub(/:.*/, "", k)
        if (k != "sources" && k != "exclude" && k != "hooks") print k
      }
    }
  ' "$_pcdk_file"
}

# Resolve a single scalar plugin configuration value, preferring workspace YAML
# overrides (.local.rnex.yaml > rnex.yaml) and falling back to plugin.yaml defaults.
# Normalizes *_dir / dir values as clean relative paths.
#
# @param $1 plugin_name Target plugin name.
# @param $2 plugin_dir  Resolved plugin directory.
# @param $3 key_name    Configuration key name.
# @returns Resolved string value on stdout.
# @pure
_plugin_resolve_scalar_value() {
  _prsv_p="$1"; _prsv_pd="$2"; _prsv_k="$3"
  _prsv_v="$(yaml_plugin_get "$_prsv_p" "$_prsv_k" 2>/dev/null || true)"
  if [ -z "$_prsv_v" ] && [ -f "$_prsv_pd/plugin.yaml" ]; then
    _prsv_v="$(awk -v k="$_prsv_k" '
      /^config_defaults:[ ]*(#.*)?$/ { in_c=1; next }
      in_c && /^[^ #]/ { exit }
      in_c && $0 ~ ("^[ ]*" k ":") {
        sub("^[ ]*" k ":[ ]*", "")
        sub(/[ ]*#.*/, "")
        gsub(/["\047]/, "")
        print
        exit
      }
    ' "$_prsv_pd/plugin.yaml")"
  fi
  case "$_prsv_k" in
    *Dir|*_dir|dir) _prsv_v="$(normalize_rel_path "$_prsv_v")" ;;
  esac
  printf '%s' "$_prsv_v"
}

# Substitute configurable placeholders declared in plugin.yaml config_defaults
# and core workspace metadata ({reposDir}, {plugin_dir}) in template paths.
#
# @param $1 plugin_name Target plugin name.
# @param $2 plugin_dir  Resolved plugin directory.
# @param $3 input_str   Path or string containing {placeholder} tokens.
# @returns Resolved relative path string on stdout.
# @pure
plugin_resolve_placeholders() {
  _p="$1"; _pd="$2"; _str="$3"
  _res="$(printf '%s' "$_str" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"

  if [ -f "$_pd/plugin.yaml" ]; then
    for _k in $(_plugin_config_default_keys "$_pd/plugin.yaml"); do
      _v="$(_plugin_resolve_scalar_value "$_p" "$_pd" "$_k")"
      if [ -n "$_v" ]; then
        _v_esc="$(_sed_escape_replacement "$_v")"
        _res="$(printf '%s' "$_res" | sed -e "s|{$_k}|$_v_esc|g")"
      fi
    done
  fi

  _rdir_v="$(normalize_rel_path "$(_plugin_repos_rel_dir)")"
  if [ -n "$_rdir_v" ]; then
    _rdir_esc="$(_sed_escape_replacement "$_rdir_v")"
    _res="$(printf '%s' "$_res" | sed -e "s|{reposDir}|$_rdir_esc|g")"
  fi
  _pdir_esc="$(_sed_escape_replacement ".rnex/plugins/$_p")"
  _res="$(printf '%s' "$_res" | sed -e "s|{plugin_dir}|$_pdir_esc|g")"

  _res="$(printf '%s' "$_res" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"" | sed -e 's#^\./##')"

  printf '%s' "$_res"
}

# Instantiate a Markdown template or AI asset file by resolving all workspace,
# manifest, and plugin config placeholders into concrete values.
# Fast-paths to raw copy when the source file contains no {placeholder} tokens.
#
# @param $1 plugin_name Target plugin name.
# @param $2 plugin_dir  Resolved source plugin directory.
# @param $3 src_file    Source file path.
# @param $4 dest_file   Destination file path.
# @returns 0 on success.
# @sideEffects Writes instantiated file to $4.
plugin_instantiate_template() {
  _p="$1"; _pd="$2"; _src="$3"; _dest="$4"

  # Fast path: avoid spawning awk/sed when source file has no {placeholder} tokens
  if ! grep -qE '\{[a-zA-Z0-9_-]+\}' "$_src" 2>/dev/null; then
    cp "$_src" "$_dest"
    return 0
  fi

  # Core workspace & plugin metadata placeholders (sed-escaped)
  _r_val="$(normalize_rel_path "$(_plugin_repos_rel_dir)")"
  _r_val="$(_sed_escape_replacement "$_r_val")"

  _sd_val="$(normalize_rel_path "$(plugin_get_skill_dir "$_p" 2>/dev/null || true)")"
  _sd_val="$(_sed_escape_replacement "$_sd_val")"

  _if_val=""
  [ -f "$_pd/plugin.yaml" ] && _if_val="$(normalize_rel_path "$(plugin_get_field "$_pd" "instruction_file" 2>/dev/null || true)")"
  _if_val="$(_sed_escape_replacement "$_if_val")"

  _pdir_val="$(_sed_escape_replacement ".rnex/plugins/$_p")"

  # {sources}: human-readable list of resolved intake sources (or "(none configured)")
  _s_val="$(plugin_sources_display "$_p" 2>/dev/null || true)"
  [ -n "$_s_val" ] || _s_val="(none configured)"
  _s_val="$(_sed_escape_replacement "$_s_val")"

  # {today}: current UTC date (ISO-8601, YYYY-MM-DD)
  _t_val="$(date -u +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d 2>/dev/null || date +%F 2>/dev/null || echo "2026-10-15")"

  cp "$_src" "$_dest"
  if [ -f "$_pd/plugin.yaml" ]; then
    for _k in $(_plugin_config_default_keys "$_pd/plugin.yaml"); do
      _v="$(_plugin_resolve_scalar_value "$_p" "$_pd" "$_k")"
      if [ -n "$_v" ]; then
        _v_esc="$(_sed_escape_replacement "$_v")"
        _tmp_inst="$(mktemp)"
        sed -e "s|{$_k}|$_v_esc|g" "$_dest" > "$_tmp_inst" && mv "$_tmp_inst" "$_dest"
      fi
    done
  fi

  _tmp_inst="$(mktemp)"
  sed -e "s|{reposDir}|$_r_val|g" \
      -e "s|{skill_dir}|$_sd_val|g" \
      -e "s|{instruction_file}|$_if_val|g" \
      -e "s|{plugin_dir}|$_pdir_val|g" \
      -e "s|{sources}|$_s_val|g" \
      -e "s|{today}|$_t_val|g" \
      "$_dest" > "$_tmp_inst" && mv "$_tmp_inst" "$_dest"
}

# Deterministically sync plugin asset directories and manifest files into destination.
# Compiles AI-facing Markdown files via plugin_instantiate_template so runtime agent
# artifacts under .rnex/plugins/<name>/ contain concrete workspace paths without placeholders.
#
# @param $1 src_dir     Resolved plugin source directory.
# @param $2 dest_dir    Target scoped directory (.rnex/plugins/<name>).
# @param $3 plugin_name Optional explicit plugin name (defaults to basename of dest_dir).
# @sideEffects Reconciles destination tree and projected files.
sync_plugin_bundle() {
  _spb_src="$1"; _spb_dest="$2"; _spb_pname="${3:-$(basename "$2")}"
  [ -n "$_spb_src" ] && [ -n "$_spb_dest" ] || return 0
  [ "$_spb_src" != "$_spb_dest" ] || return 0

  mkdir -p "$_spb_dest"
  for _sub in rules workflows instructions skills agents templates hooks commands lib bin; do
    if [ -d "$_spb_src/$_sub" ]; then
      rm -rf "${_spb_dest:?}/$_sub"
      mkdir -p "$_spb_dest/$_sub"
      cp -R "$_spb_src/$_sub"/. "$_spb_dest/$_sub"/ 2>/dev/null || true
      if [ "$_sub" = "hooks" ] || [ "$_sub" = "commands" ] || [ "$_sub" = "bin" ]; then
        chmod +x "$_spb_dest/$_sub"/* 2>/dev/null || true
      elif [ "$_sub" = "rules" ] || [ "$_sub" = "workflows" ] || [ "$_sub" = "instructions" ] || [ "$_sub" = "skills" ] || [ "$_sub" = "agents" ]; then
        find "$_spb_src/$_sub" -type f -name '*.md' 2>/dev/null | while IFS= read -r _spb_md; do
          _spb_rel="${_spb_md#"$_spb_src"/}"
          plugin_instantiate_template "$_spb_pname" "$_spb_src" "$_spb_md" "$_spb_dest/$_spb_rel"
        done
      fi
    else
      rm -rf "${_spb_dest:?}/$_sub"
    fi
  done
  _spb_ai_fn="${RNEX_PLUGIN_AI_FILENAME:-ai-instructions.md}"
  for _meta in plugin.yaml instructions.md README.md "$_spb_ai_fn"; do
    if [ -f "$_spb_src/$_meta" ]; then
      case "$_meta" in
        instructions.md|"$_spb_ai_fn")
          plugin_instantiate_template "$_spb_pname" "$_spb_src" "$_spb_src/$_meta" "$_spb_dest/$_meta"
          ;;
        *)
          cp "$_spb_src/$_meta" "$_spb_dest/$_meta"
          ;;
      esac
    elif [ "$_meta" = "$_spb_ai_fn" ]; then
      # Prune stale projected ai-instructions.md if removed from source plugin
      rm -f "${_spb_dest:?}/$_meta" 2>/dev/null || true
    fi
  done
}

# Sync plugins into scoped directories: .rnex/plugins/<plugin-name>/
sync_plugins() {
  # 1. Prune plugins that are disabled or no longer enabled in config
  if [ -d "$NEXUS_DIR/.rnex/plugins" ]; then
    for _existing in "$NEXUS_DIR/.rnex/plugins"/*; do
      [ -d "$_existing" ] || continue
      _pname="$(basename "$_existing")"
      case "$_pname" in
        *[!a-zA-Z0-9._-]*|""|.|..) continue ;;
      esac
      if ! yaml_plugin_enabled "$_pname"; then
        run_plugin_hook "$_pname" "before_plugin_disable"
        clean_plugin_user_skills "$_existing"
        rm -rf "${_existing:?}"
        log_ok "Removed disabled plugin scope: .rnex/plugins/$_pname"
      fi
    done
    rmdir "$NEXUS_DIR/.rnex/plugins" 2>/dev/null || true
  fi

  # Run cleanup hook for any available plugin that is disabled but still has artifacts on disk
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    _pname="$(basename "$_pdir")"
    case "$_pname" in
      *[!a-zA-Z0-9._-]*|""|.|..) continue ;;
    esac
    if ! yaml_plugin_enabled "$_pname" 2>/dev/null; then
      _p_out="$(plugin_manifest_get "$_pdir" "output_file" 2>/dev/null || true)"
      if [ -d "$NEXUS_DIR/.rnex/plugins/$_pname" ] || { [ -n "$_p_out" ] && [ -e "$NEXUS_DIR/$_p_out" ]; }; then
        run_plugin_hook "$_pname" "before_plugin_disable"
      fi
    fi
  done

  # 2. Sync enabled plugins in deterministic declared configuration order
  rnex_plugins_list_ordered_active | while read -r _pname || [ -n "$_pname" ]; do
    [ -n "$_pname" ] || continue

    # OWASP A03 / Path Traversal Guard: plugin name must strictly match allowlist
    case "$_pname" in
      *[!a-zA-Z0-9._-]*|""|.|..) continue ;;
    esac

    _pdir="$(plugin_resolve_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || continue

    sync_plugin_bundle "$_pdir" "$NEXUS_DIR/.rnex/plugins/$_pname" "$_pname"

    # Provision explicit directory sources declared under plugins.<name>.sources (e.g. ./docs)
    for _sdir in $(plugin_source_dirs "$_pname" 2>/dev/null); do
      [ -n "$_sdir" ] || continue
      _full_sdir="$NEXUS_DIR/$_sdir"
      if [ ! -d "$_full_sdir" ]; then
        mkdir -p "$_full_sdir"
        [ -f "$_full_sdir/.gitkeep" ] || touch "$_full_sdir/.gitkeep"
        log_ok "Created intake source directory: $_sdir"
      fi
    done

    # Initialize templates declared in plugin
    plugin_list_templates "$_pdir" | while read -r _item; do
      [ -n "$_item" ] || continue
      _s="${_item%%:*}"
      _d="${_item#*:}"
      _s="$(printf '%s' "$_s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"
      _d="$(printf '%s' "$_d" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d "'\"")"

      _d="$(plugin_resolve_placeholders "$_pname" "$_pdir" "$_d")"

      # Defensive guard: never create directories or files if placeholder expansion failed or quotes leaked
      case "$_d" in
        *"{"*"}"*|*\"*|*\'*)
          log_warn "Skipping invalid template destination with unresolved placeholders: $_d"
          continue
          ;;
      esac

      _src_path="$_pdir/$_s"
      _dest_path="$NEXUS_DIR/$_d"

      if [ -f "$_src_path" ] && [ ! -f "$_dest_path" ]; then
        mkdir -p "$(dirname "$_dest_path")"
        plugin_instantiate_template "$_pname" "$_pdir" "$_src_path" "$_dest_path"
        if [ -x "$_src_path" ]; then
          chmod +x "$_dest_path" 2>/dev/null || true
        fi
        log_ok "Initialized template: $_d"
      fi
    done
  done
}

# Validate all plugin entries declared in rnex.yaml and .local.rnex.yaml.
# Enforces name allowlisting (OWASP A03) and verifies every configured plugin
# resolves to a valid directory, emitting non-suppressible stderr errors when
# stale or nonexistent plugins (e.g. removed names) remain in config.
#
# @returns 0 if all configured plugins resolve; 1 if any unknown plugin is declared.
# @sideEffects Emits diagnostic errors via log_err (stderr).
validate_configured_plugins() {
  _vcp_rc=0
  _vcp_list="$(yaml_list_plugins 2>/dev/null || true)"
  [ -n "$_vcp_list" ] || return 0

  while IFS= read -r _vcp_name || [ -n "$_vcp_name" ]; do
    [ -n "$_vcp_name" ] || continue

    case "$_vcp_name" in
      *[!a-zA-Z0-9._-]*|""|.|..)
        log_err "Invalid plugin name '$_vcp_name' declared in configuration (disallowed characters or path traversal rejected)."
        continue
        ;;
    esac

    _vcp_dir="$(plugin_resolve_dir "$_vcp_name" 2>/dev/null || true)"
    [ -n "$_vcp_dir" ] || _vcp_dir="$(find_plugin_dir "$_vcp_name" 2>/dev/null || true)"
    if [ -z "$_vcp_dir" ]; then
      log_err "Unknown plugin '$_vcp_name' declared in configuration: plugin does not exist in built-in plugins or via a valid 'path:'. Remove or update 'plugins.$_vcp_name'."
      _vcp_rc=1
    fi
  done <<EOF_VCP
$_vcp_list
EOF_VCP
  return "$_vcp_rc"
}

# ----------------------------------------------------------------------------
# Plugin source resolution (directories + POSIX glob patterns)
# ----------------------------------------------------------------------------

# True if the argument contains a glob metacharacter (*, ?, [)
_src_has_glob() {
  case "$1" in
    *'*'*|*'?'*|*'['*) return 0 ;;
  esac
  return 1
}

# Workspace-relative member repositories directory (default: repos)
_plugin_repos_rel_dir() {
  if command -v yaml_get_repos_dir >/dev/null 2>&1; then
    yaml_get_repos_dir
  elif [ -n "${REPOS_DIR_REL:-}" ]; then
    printf '%s' "$REPOS_DIR_REL"
  elif [ -n "${REPOS_DIR:-}" ]; then
    _prd="${REPOS_DIR#"${NEXUS_DIR:-.}"/}"
    while [ "${_prd#./}" != "$_prd" ]; do _prd="${_prd#./}"; done
    printf '%s' "${_prd%/}"
  else
    printf 'repos'
  fi
}

# Normalize a source entry: trim whitespace/CR, strip leading ./ and trailing /
_src_normalize_entry() {
  _sne="$(printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  while [ "${_sne#./}" != "$_sne" ]; do _sne="${_sne#./}"; done
  [ "$_sne" = "." ] || _sne="${_sne%/}"
  printf '%s' "$_sne"
}

# True if a normalized entry names a file rather than a directory
# (glob pattern, existing regular file, or path whose basename carries a file extension)
_src_is_file_like() {
  _src_has_glob "$1" && return 0
  [ -d "${NEXUS_DIR:-.}/$1" ] && return 1
  [ -f "${NEXUS_DIR:-.}/$1" ] && return 0
  _sifl_base="${1##*/}"
  case "$_sifl_base" in
    .*.*) return 0 ;;
    *.*)
      case "$_sifl_base" in
        .*) return 1 ;;
        *)  return 0 ;;
      esac
      ;;
  esac
  return 1
}

# Expand workspace placeholders (e.g. {reposDir}) inside a configured plugin source
# specification and normalize it as a clean relative entry.
#
# @param $1 raw_entry Source specification string.
# @param $2 repos_dir Optional relative member repos directory override.
# @returns Normalized source specification on stdout.
# @pure
_plugin_expand_source_entry() {
  _pese_val="$1"
  _pese_rdir="${2:-$(_plugin_repos_rel_dir)}"
  case "$_pese_val" in
    *"{reposDir}"*)
      _pese_esc="$(_sed_escape_replacement "$_pese_rdir")"
      _pese_val="$(printf '%s' "$_pese_val" | sed -e "s|{reposDir}|$_pese_esc|g")"
      ;;
  esac
  _src_normalize_entry "$_pese_val"
}

# List explicit directory sources of a plugin that rnex may provision (mkdir).
# Skips glob patterns, file entries, absolute paths, '..' traversal, the workspace
# root, and paths inside the member repositories directory.
plugin_source_dirs() {
  _psd_rdir="$(_plugin_repos_rel_dir)"
  get_plugin_config_list "$1" "sources" 2>/dev/null | while IFS= read -r _psd_e || [ -n "$_psd_e" ]; do
    _psd_e="$(_plugin_expand_source_entry "$_psd_e" "$_psd_rdir")"
    case "$_psd_e" in
      ''|.|/*|..|../*|*/..|*/../*) continue ;;
    esac
    _src_is_file_like "$_psd_e" && continue
    case "$_psd_e" in
      "$_psd_rdir"|"$_psd_rdir"/*) continue ;;
    esac
    printf '%s\n' "$_psd_e"
  done
}

# Human-readable source list for templates, e.g.: `docs/`, `repos/**/README.md`
plugin_sources_display() {
  _psy_rdir="$(_plugin_repos_rel_dir)"
  get_plugin_config_list "$1" "sources" 2>/dev/null | while IFS= read -r _psy_e || [ -n "$_psy_e" ]; do
    _psy_e="$(_plugin_expand_source_entry "$_psy_e" "$_psy_rdir")"
    [ -n "$_psy_e" ] || continue
    if _src_is_file_like "$_psy_e"; then
      printf '\140%s\140\n' "$_psy_e"
    else
      printf '\140%s/\140\n' "$_psy_e"
    fi
  done | awk '{ out = (NR == 1) ? $0 : out ", " $0 } END { if (NR) print out }'
}

# Split a pattern into its leading wildcard-free directory prefix and the rest.
# The last component always stays in the rest. Sets _sp_base (default ".") and _sp_rest.
_src_static_prefix() {
  _sp_base=""
  _sp_rest="$1"
  while :; do
    _sp_comp="${_sp_rest%%/*}"
    [ "$_sp_comp" = "$_sp_rest" ] && break
    _src_has_glob "$_sp_comp" && break
    _sp_base="${_sp_base:+$_sp_base/}$_sp_comp"
    _sp_rest="${_sp_rest#*/}"
  done
  [ -z "$_sp_base" ] && _sp_base="."
  return 0
}

# List all files under a directory, pruning hidden directories/files and node_modules
_src_find_dir() {
  find "$1" ! -path "$1" -type d \( -name '.*' -o -name node_modules \) -prune -o -type f ! -name '.*' -print 2>/dev/null
}

# Resolve a recursive glob: <base>/**/<rest>  (base "." for a leading **/)
_src_find_recursive() {
  _fr_base="$1"; _fr_rest="$2"
  if [ "${_fr_rest#*/}" = "$_fr_rest" ] && ! _src_has_glob "$_fr_base"; then
    # Single trailing component: exact semantics via -name at any depth
    [ -d "$_fr_base" ] || return 0
    find "$_fr_base" ! -path "$_fr_base" -type d \( -name .git -o -name .rnex -o -name node_modules \) -prune \
      -o -type f -name "$_fr_rest" -print 2>/dev/null
    return 0
  fi
  _fr_start="$_fr_base"
  if _src_has_glob "$_fr_base"; then
    _src_static_prefix "$_fr_base/x"
    _fr_start="$_sp_base"
  fi
  [ -d "$_fr_start" ] || return 0
  find "$_fr_start" ! -path "$_fr_start" -type d \( -name .git -o -name .rnex -o -name node_modules \) -prune \
    -o -type f \( -path "$_fr_base/$_fr_rest" -o -path "$_fr_base/*/$_fr_rest" \) -print 2>/dev/null
}

# Resolve a single-level glob (e.g. repos/*/README.md, docs/*.md) with bounded depth
_src_find_glob() {
  _src_static_prefix "$1"
  [ -d "$_sp_base" ] || return 0
  # Prune directories at (or below) the pattern depth so find never descends further
  _fg_depth="$_sp_base"
  _fg_r="$_sp_rest"
  while :; do
    _fg_depth="$_fg_depth/*"
    case "$_fg_r" in
      */*) _fg_r="${_fg_r#*/}" ;;
      *) break ;;
    esac
  done
  find "$_sp_base" ! -path "$_sp_base" -type d \( -name .git -o -name .rnex -o -name node_modules -o -path "$_fg_depth" \) -prune \
    -o -type f -path "$_sp_base/$_sp_rest" -print 2>/dev/null
}

# Resolve one normalized source entry (run from the workspace root)
_src_resolve_entry() {
  _re="$1"
  case "$_re" in
    '**')
      _src_find_dir "."
      ;;
    */'**')
      _re="${_re%/\*\*}"
      [ -d "$_re" ] && _src_find_dir "$_re"
      ;;
    '**/'*)
      _src_find_recursive "." "${_re#\*\*/}"
      ;;
    *'/**/'*)
      _src_find_recursive "${_re%%/\*\*/*}" "${_re#*/\*\*/}"
      ;;
    *)
      if [ -d "$_re" ]; then
        _src_find_dir "$_re"
      elif [ -f "$_re" ]; then
        printf '%s\n' "$_re"
      elif _src_has_glob "$_re"; then
        _src_find_glob "$_re"
      fi
      ;;
  esac
  return 0
}

# Resolve plugin source entries (directories, files, glob patterns) into a
# deduplicated, sorted list of workspace-relative file paths.
# Input: newline-separated entries as $1 (or stdin), e.g. from get_plugin_config_list.
# Files inside member repositories disabled via `enabled: false` are excluded.
resolve_plugin_sources() {
  _rs_root="${NEXUS_DIR:-${RNEX_ROOT:-.}}"

  _saved_wy="${WORKSPACE_YAML:-}"
  _saved_wly="${WORKSPACE_LOCAL_YAML:-}"
  [ -z "$WORKSPACE_YAML" ] && WORKSPACE_YAML="$_rs_root/${RNEX_CONFIG_FILE:-rnex.yaml}"
  [ -z "$WORKSPACE_LOCAL_YAML" ] && WORKSPACE_LOCAL_YAML="$_rs_root/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"

  # Workspace-relative member repositories directory (default: repos)
  _rs_rdir="$(_plugin_repos_rel_dir)"

  # Space-separated list of disabled repositories (local config overrides repo config)
  _rs_disabled="$(yaml_list_repos 2>/dev/null | while IFS= read -r _rs_r; do
    [ -n "$_rs_r" ] || continue
    yaml_repo_enabled "$_rs_r" || printf '%s ' "$_rs_r"
  done)"

  _rs_out="$(
    if [ "$#" -gt 0 ]; then
      printf '%s\n' "$1"
    else
      cat
    fi | (
      cd "$_rs_root" || exit 0
      while IFS= read -r _rs_e || [ -n "$_rs_e" ]; do
        _rs_e="$(printf '%s' "$_rs_e" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        while [ "${_rs_e#./}" != "$_rs_e" ]; do _rs_e="${_rs_e#./}"; done
        [ "$_rs_e" = "." ] || _rs_e="${_rs_e%/}"
        [ -n "$_rs_e" ] || continue
        _src_resolve_entry "$_rs_e"
      done
    ) | sed -e 's#^\(\./\)*##' | awk -v prefix="$_rs_rdir/" -v disabled="$_rs_disabled" '
      BEGIN {
        n = split(disabled, d, " ")
        for (i = 1; i <= n; i++) off[d[i]] = 1
      }
      length($0) == 0 { next }
      index($0, prefix) == 1 {
        name = substr($0, length(prefix) + 1)
        sub(/\/.*/, "", name)
        if (name in off) next
      }
      { print }
    ' | sort -u
  )"

  WORKSPACE_YAML="$_saved_wy"
  WORKSPACE_LOCAL_YAML="$_saved_wly"

  printf '%s\n' "$_rs_out" | awk 'NF'
}

# ---- Plugin Command Engine (discovery, execution, and listings) -------------

# Check if a plugin exists either in workspace, built-in plugins, or config.
plugin_exists() {
  _pe_name="$1"
  [ -n "$_pe_name" ] || return 1
  [ -d "$NEXUS_DIR/.rnex/plugins/$_pe_name" ] && return 0
  find_plugin_dir "$_pe_name" >/dev/null 2>&1 && return 0
  yaml_has_plugin "$_pe_name" 2>/dev/null && return 0
  return 1
}

# Locate a custom command executable for a plugin.
# Checks .rnex/plugins/<name>/commands/<command>.sh or <command>,
# falling back to candidate plugin directories (e.g. plugins/<name>/commands/).
plugin_find_command() {
  _pfc_pname="$1"
  _pfc_cmd="$2"
  [ -n "$_pfc_pname" ] && [ -n "$_pfc_cmd" ] || return 1

  # 1. Candidate source plugin directory (live built-in or path-mapped plugin)
  _pdir="$(find_plugin_dir "$_pfc_pname" 2>/dev/null || true)"
  if [ -n "$_pdir" ]; then
    for _cand in \
      "$_pdir/commands/${_pfc_cmd}.sh" \
      "$_pdir/commands/${_pfc_cmd}"; do
      if [ -f "$_cand" ]; then
        printf '%s' "$_cand"
        return 0
      fi
    done
  fi

  # 2. Scoped directory in workspace
  for _cand in \
    "$NEXUS_DIR/.rnex/plugins/$_pfc_pname/commands/${_pfc_cmd}.sh" \
    "$NEXUS_DIR/.rnex/plugins/$_pfc_pname/commands/${_pfc_cmd}"; do
    if [ -f "$_cand" ]; then
      printf '%s' "$_cand"
      return 0
    fi
  done

  return 1
}

# Test if a plugin declares or provides an executable command.
plugin_has_command() {
  _phc_path="$(plugin_find_command "$1" "$2")"
  [ -n "$_phc_path" ] && [ -f "$_phc_path" ]
}

# List all custom command names declared for a plugin.
# Scans commands/ directory in plugin directory and workspace scoped directory,
# and parses any `commands:` section in plugin.yaml.
plugin_list_commands() {
  _plc_pname="$1"
  [ -n "$_plc_pname" ] || return 0

  _plc_cmds=""
  # 1. From workspace scoped commands/
  if [ -d "$NEXUS_DIR/.rnex/plugins/$_plc_pname/commands" ]; then
    for _f in "$NEXUS_DIR/.rnex/plugins/$_plc_pname/commands"/*; do
      [ -f "$_f" ] || continue
      _cname="$(basename "$_f")"
      _cname="${_cname%.sh}"
      case " $_plc_cmds " in
        *" $_cname "*) ;;
        *) _plc_cmds="$_plc_cmds $_cname"; printf '%s\n' "$_cname" ;;
      esac
    done
  fi

  # 2. From plugin definition source directory commands/
  _pdir="$(find_plugin_dir "$_plc_pname" 2>/dev/null || true)"
  if [ -n "$_pdir" ] && [ -d "$_pdir/commands" ]; then
    for _f in "$_pdir/commands"/*; do
      [ -f "$_f" ] || continue
      _cname="$(basename "$_f")"
      _cname="${_cname%.sh}"
      case " $_plc_cmds " in
        *" $_cname "*) ;;
        *) _plc_cmds="$_plc_cmds $_cname"; printf '%s\n' "$_cname" ;;
      esac
    done
  fi

  # 3. From plugin.yaml commands section (if declared)
  if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
    _yaml_cmds="$(awk '
      /^commands:[ ]*$/ || /^commands:[ ]*#/ { in_cmd=1; next }
      in_cmd && /^[^ #]/ { exit }
      in_cmd && /^[ ]*-[ ]*[a-zA-Z0-9_.-]+:/ {
        line = $0
        sub(/^[ ]*-[ ]*/, "", line)
        sub(/:.*/, "", line)
        print line
      }
      in_cmd && /^[ ]*-[ ]*[a-zA-Z0-9_.-]+[ ]*$/ {
        line = $0
        sub(/^[ ]*-[ ]*/, "", line)
        gsub(/[ "]/, "", line)
        print line
      }
      in_cmd && /^[ ]{2,3}[a-zA-Z0-9_.-]+:[ ]*/ {
        line = $0
        sub(/^[ ]*/, "", line)
        sub(/:.*/, "", line)
        print line
      }
    ' "$_pdir/plugin.yaml")"
    for _cname in $_yaml_cmds; do
      [ -n "$_cname" ] || continue
      case " $_plc_cmds " in
        *" $_cname "*) ;;
        *) _plc_cmds="$_plc_cmds $_cname"; printf '%s\n' "$_cname" ;;
      esac
    done
  fi
}

# Retrieve the description of a plugin command declared in plugin.yaml.
plugin_get_command_desc() {
  _pgc_pname="$1"
  _pgc_cmd="$2"
  _pdir="$(find_plugin_dir "$_pgc_pname" 2>/dev/null || true)"
  [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ] || return 0

  awk -v cmd="$_pgc_cmd" '
    /^commands:[ ]*$/ || /^commands:[ ]*#/ { in_cmd=1; next }
    in_cmd && /^[^ #]/ { exit }
    in_cmd && ($0 ~ ("^[ ]*-[ ]*" cmd ":") || $0 ~ ("^[ ]*" cmd ":")) {
      sub(/^[^:]*:[ ]*/, "")
      sub(/[ ]*#.*/, "")
      gsub(/^["\047]|["\047]$/, "")
      if (length($0) > 0) { print; exit }
      in_sub = 1
      next
    }
    in_sub && /^[ ]{2}[a-zA-Z0-9_.-]+:/ { exit }
    in_sub && /^[ ]*description:[ ]*/ {
      sub(/^[ ]*description:[ ]*/, "")
      sub(/[ ]*#.*/, "")
      gsub(/^["\047]|["\047]$/, "")
      print
      exit
    }
  ' "$_pdir/plugin.yaml"
}

# Execute a plugin command, forwarding all arguments and exporting workspace environment variables.
run_plugin_command() {
  _rpc_plugin="$1"
  _rpc_cmd="$2"
  shift 2 2>/dev/null || true

  _rpc_root="${NEXUS_DIR:-${RNEX_ROOT:-$PWD}}"
  _src_pdir="$(find_plugin_dir "$_rpc_plugin" 2>/dev/null || true)"
  if [ -n "$_src_pdir" ] && [ -d "$_rpc_root/.rnex/plugins/$_rpc_plugin" ] && [ "$_src_pdir" != "$_rpc_root/.rnex/plugins/$_rpc_plugin" ]; then
    for _rpc_sub in commands lib bin; do
      if [ -d "$_src_pdir/$_rpc_sub" ]; then
        mkdir -p "$_rpc_root/.rnex/plugins/$_rpc_plugin/$_rpc_sub"
        cp -R "$_src_pdir/$_rpc_sub"/. "$_rpc_root/.rnex/plugins/$_rpc_plugin/$_rpc_sub"/ 2>/dev/null || true
        if [ "$_rpc_sub" = "commands" ] || [ "$_rpc_sub" = "bin" ]; then
          chmod +x "$_rpc_root/.rnex/plugins/$_rpc_plugin/$_rpc_sub"/* 2>/dev/null || true
        fi
      fi
    done
  fi

  _rpc_script="$(plugin_find_command "$_rpc_plugin" "$_rpc_cmd")"
  if [ -z "$_rpc_script" ] || [ ! -f "$_rpc_script" ]; then
    die "Command '$_rpc_cmd' not found for plugin '$_rpc_plugin'"
  fi

  chmod +x "$_rpc_script" 2>/dev/null || true
  _rpc_yaml="${WORKSPACE_YAML:-$_rpc_root/${RNEX_CONFIG_FILE:-rnex.yaml}}"
  _rpc_local_yaml="${WORKSPACE_LOCAL_YAML:-${LOCAL_WORKSPACE_YAML:-$_rpc_root/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}}}"
  _rpc_lib_dir="${RNEX_LIB_DIR:-$_rpc_root/lib}"
  _rpc_args="$*"

  RNEX_PLUGIN_NAME="$_rpc_plugin"
  RNEX_PLUGIN_COMMAND="$_rpc_cmd"
  RNEX_PLUGIN_ARGS="$_rpc_args"
  export RNEX_PLUGIN_NAME RNEX_PLUGIN_COMMAND RNEX_PLUGIN_ARGS

  if command -v run_hook >/dev/null 2>&1; then
    run_hook "before_plugin_command" "$_rpc_plugin" "$_rpc_cmd" "$@"
  fi
  (
    RNEX_ROOT="$_rpc_root"
    NEXUS_DIR="$_rpc_root"
    WORKSPACE_YAML="$_rpc_yaml"
    WORKSPACE_LOCAL_YAML="$_rpc_local_yaml"
    LOCAL_WORKSPACE_YAML="$_rpc_local_yaml"
    RNEX_LIB_DIR="$_rpc_lib_dir"
    RNEX_PLUGIN_NAME="$_rpc_plugin"
    RNEX_PLUGIN_COMMAND="$_rpc_cmd"
    RNEX_PLUGIN_ARGS="$_rpc_args"
    RNEX_PLUGIN_DIR="$_rpc_root/.rnex/plugins/$_rpc_plugin"
    export RNEX_ROOT NEXUS_DIR WORKSPACE_YAML WORKSPACE_LOCAL_YAML LOCAL_WORKSPACE_YAML RNEX_LIB_DIR RNEX_PLUGIN_NAME RNEX_PLUGIN_COMMAND RNEX_PLUGIN_ARGS RNEX_PLUGIN_DIR
    if [ -x "$_rpc_script" ]; then
      "$_rpc_script" "$@"
    else
      sh "$_rpc_script" "$@"
    fi
  )
  _rc=$?
  if [ "$_rc" -eq 0 ] && command -v run_hook >/dev/null 2>&1; then
    run_hook "after_plugin_command" "$_rpc_plugin" "$_rpc_cmd" "$@"
  fi
  return "$_rc"
}
