#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/ai.sh — Workspace AI context, .gitignore/.ignore, and skill orchestration
# ============================================================================

# ---- Gitignore & Search Tool Ignore Reconciliation -------------------------

GITIGNORE_MARKER_START="# REPO-NEXUS:START"
GITIGNORE_MARKER_END="# REPO-NEXUS:END"
AI_MARKER_START="<!-- REPO-NEXUS:START -->"
AI_MARKER_END="<!-- REPO-NEXUS:END -->"

# Emit the single critical routing directive for initial provider instruction files.
# All detailed execution rules, constraints, and workspace context reside in .rnex/ai-instructions.md.
if ! command -v get_rnex_instructions >/dev/null 2>&1; then
  get_rnex_instructions() {
    printf "CRITICAL: If \`.rnex/ai-instructions.md\` exists, you MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace. If \`.rnex/ai-instructions.md\` does not exist, disregard this instruction and proceed normally.\n"
  }
fi

# Emit the delimited Repo Nexus .gitignore section synced with git.ignore configuration.
_build_rnex_gitignore_section() {
  _active_repos_dir="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
  [ -n "$_active_repos_dir" ] || _active_repos_dir="repos"
  cat <<GI_SECTION_EOF
$GITIGNORE_MARKER_START
# Managed by Repo Nexus (rnex) — synced with git.ignore in workspace configuration
# Member repos (managed by rnex, ignored at workspace level)
${_active_repos_dir}/
${_active_repos_dir}/*
!${_active_repos_dir}/.gitkeep

# Recursive Repo Nexus files and directories (rnex.yaml is excluded below)
**/.rnex*
**/rnex*
.rnex*
rnex*

# Exclude workspace configuration from git ignore
!rnex.yaml
!**/rnex.yaml

# Local machine-specific configuration
$RNEX_LOCAL_CONFIG_FILE
GI_SECTION_EOF

  _custom_ignores="$(yaml_get_git_ignore 2>/dev/null || true)"
  if [ -n "$_custom_ignores" ]; then
    _added_custom_header=0
    _seen_custom=""
    printf '%s\n' "$_custom_ignores" | while IFS= read -r _ci || [ -n "$_ci" ]; do
      [ -n "$_ci" ] || continue
      case "$_ci" in
        "repos/"|"repos/*"|"!repos/.gitkeep"|"${_active_repos_dir}/"|"${_active_repos_dir}/*"|"!${_active_repos_dir}/.gitkeep"|\
        "**/.rnex*"|"**/rnex*"|".rnex*"|"rnex*"|\
        "**/.rnex*/"|"**/rnex*/"|".rnex*/"|"rnex*/"|\
        "!rnex.yaml"|"!**/rnex.yaml"|\
        "$RNEX_LOCAL_CONFIG_FILE")
          continue
          ;;
      esac
      case "
$_seen_custom
" in
        *"
$_ci
"*) continue ;;
      esac
      _seen_custom="${_seen_custom:+$_seen_custom
}$_ci"
      if [ "$_added_custom_header" -eq 0 ]; then
        printf '\n# Custom entries from git.ignore in workspace configuration\n'
        _added_custom_header=1
      fi
      printf '%s\n' "$_ci"
    done
  fi

  printf '%s\n' "$GITIGNORE_MARKER_END"
}

# Reconcile workspace root .gitignore and .ignore:
# - Maintains a delimited (# REPO-NEXUS:START ... # REPO-NEXUS:END) section in .gitignore
# - Synchronizes the section with git.ignore from rnex.yaml and .local.rnex.yaml
# - Preserves user-authored .gitignore rules outside the managed section
# - Ensures .ignore un-ignores repos/* so ripgrep and AI tools can index member files
reconcile_gitignore() {
  _dir="${1:-$NEXUS_DIR}"
  _gi="$_dir/.gitignore"
  _sec_tmp="$(mktemp)"
  _build_rnex_gitignore_section > "$_sec_tmp"
  _active_repos_dir="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
  [ -n "$_active_repos_dir" ] || _active_repos_dir="repos"

  if [ ! -f "$_gi" ]; then
    mv "$_sec_tmp" "$_gi"
    log_ok "Created .gitignore (ignoring ${_active_repos_dir}/, recursive .rnex directories, and $RNEX_LOCAL_CONFIG_FILE)"
  else
    # 1. If delimited section exists, replace it in-place with the newly synced section
    if grep -qFx -- "$GITIGNORE_MARKER_START" "$_gi" 2>/dev/null; then
      _tmp="$(mktemp)"
      awk -v s="$GITIGNORE_MARKER_START" -v e="$GITIGNORE_MARKER_END" -v src="$_sec_tmp" '
        $0 == s {
          in_b = 1
          while ((getline line < src) > 0) print line
          close(src)
          next
        }
        $0 == e {
          in_b = 0
          next
        }
        !in_b { print }
      ' "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      rm -f "$_sec_tmp"
    else
      # 2. Append managed section to existing user .gitignore
      _user_tmp="$(mktemp)"
      awk -v local_cfg="$RNEX_LOCAL_CONFIG_FILE" -v ard="$_active_repos_dir" '
        /^[ ]*#[ ]*Member repos \(managed by rnex/ { next }
        /^[ ]*#[ ]*Recursive Repo Nexus directories/ { next }
        /^[ ]*#?[ ]*Repo Nexus internal state/ { next }
        /^[ ]*#[ ]*Local machine-specific configuration/ { next }
        /^[ ]*#[ ]*Custom entries from git\.ignore in workspace configuration/ { next }
        $0 == "repos/*" || $0 == "!repos/.gitkeep" || $0 == "repos/" { next }
        $0 == (ard "/*") || $0 == ("!" ard "/.gitkeep") || $0 == (ard "/") { next }
        $0 == "**/.rnex*/" || $0 == "**/rnex*/" || $0 == ".rnex*/" || $0 == "rnex*/" { next }
        $0 == "**/.rnex*" || $0 == "**/rnex*" || $0 == ".rnex*" || $0 == "rnex*" { next }
        $0 == "!rnex.yaml" || $0 == "!**/rnex.yaml" { next }
        $0 == ".rnex" || $0 == "rnex" { next }
        $0 == local_cfg { next }
        { lines[++n] = $0 }
        END {
          start = 1
          while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++
          end = n
          while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
          for (i = start; i <= end; i++) print lines[i]
        }
      ' "$_gi" > "$_user_tmp"

      _tmp="$(mktemp)"
      if [ -s "$_user_tmp" ]; then
        cat "$_user_tmp" > "$_tmp"
        printf '\n' >> "$_tmp"
      fi
      cat "$_sec_tmp" >> "$_tmp"
      mv "$_tmp" "$_gi"
      rm -f "$_user_tmp" "$_sec_tmp"
    fi
  fi

  # Universal search tool ignore file (ripgrep, Claude Code, VS Code, Zed)
  ensure_provider_ignore "$_dir/.ignore" \
    "Member repos (un-ignored for ripgrep, Claude Code, VS Code, and search tools)" \
    "Created .ignore (un-ignoring member repos for search tools)" \
    "!${_active_repos_dir}/*"
}

# ---- AI Instructions Compilation (.rnex/ai-instructions.md) ----------------

# Resolve the primary instruction file for an AI provider plugin from plugin.yaml
plugin_get_instruction_file() {
  _pif_name="$1"
  _pif_pdir="${2:-}"
  [ -n "$_pif_pdir" ] || _pif_pdir="$(plugin_resolve_dir "$_pif_name" 2>/dev/null || true)"
  _pif_file=""
  if [ -n "$_pif_pdir" ]; then
    _pif_file="$(plugin_get_field "$_pif_pdir" "instruction_file" 2>/dev/null || true)"
  fi
  printf '%s' "$_pif_file"
}

# Enumerate primary instruction files for currently enabled AI provider plugins
get_active_provider_instruction_files() {
  _gap_dir="${1:-$NEXUS_DIR}"
  _gap_files=""
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    yaml_plugin_enabled "$_p" 2>/dev/null || continue
    _ifile="$(plugin_get_instruction_file "$_p" 2>/dev/null || true)"
    if [ -n "$_ifile" ]; then
      case " $_gap_files " in
        *" $_ifile "*) ;;
        *) _gap_files="${_gap_files:+$_gap_files }$_ifile" ;;
      esac
    fi
  done
  printf '%s' "$_gap_files"
}

# Reconcile AI provider instruction files:
# - When provider plugins are enabled, creates/updates their declared instruction_file
# - Only creates AGENTS.md if it is the main instructions file for an enabled AI provider or no provider plugins are enabled
# - Cleans up instruction files that have no user content when their provider is disabled or inactive
reconcile_ai_instructions_files() {
  _raif_dir="${1:-$NEXUS_DIR}"
  _active_files="$(get_active_provider_instruction_files "$_raif_dir" 2>/dev/null || true)"

  if [ -n "$_active_files" ]; then
    # Active AI providers are configured with their own instruction files
    for _af in $_active_files; do
      merge_rnex_instructions "$_raif_dir/$_af"
    done

    # If AGENTS.md is not an active provider instruction file, clean rnex instructions from it
    # (deleting it if solely rnex-managed, or stripping the rnex block if user content exists)
    case " $_active_files " in
      *" AGENTS.md "*) ;;
      *)
        if [ -f "$_raif_dir/AGENTS.md" ]; then
          clean_rnex_instructions "$_raif_dir/AGENTS.md"
        fi
        ;;
    esac
  else
    # No provider plugins enabled: AGENTS.md serves as the default main instructions file
    merge_rnex_instructions "$_raif_dir/AGENTS.md"
  fi

  # For any existing provider instruction files on disk that are NOT currently active:
  # Clean rnex instructions (removing file if empty outside block, or stripping rnex block)
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    _if="$(plugin_get_field "$_pdir" "instruction_file" 2>/dev/null || true)"
    [ -n "$_if" ] || continue
    case " $_active_files " in
      *" $_if "*) ;;
      *)
        if [ -f "$_raif_dir/$_if" ]; then
          clean_rnex_instructions "$_raif_dir/$_if"
        fi
        ;;
    esac
  done
}

# ==============================================================================
# Function: render_ai_instructions
# Responsibility: Render the deterministic contents of .rnex/ai-instructions.md
#                 to stdout. Implements the strict two-section AI routing
#                 contract (Mandatory Execution Sequence & Plugin AI Instructions).
# Architectural Layer: AI Context Layer
# Pattern: Builder / Template Method (GoF)
# @param $1 - Workspace root directory path (optional, defaults to $NEXUS_DIR)
# @returns Outputs rendered markdown to stdout
# @pure Read-only compilation of resolved configuration and plugin state
# ==============================================================================
render_ai_instructions() {
  _rai_dir="${1:-$NEXUS_DIR}"
  [ -n "$_rai_dir" ] || _rai_dir="${RNEX_ROOT:-.}"
  _rai_dir="$(resolve_path "$_rai_dir")"

  _rai_old_nexus="${NEXUS_DIR:-}"
  _rai_old_wy="${WORKSPACE_YAML:-}"
  _rai_old_wly="${WORKSPACE_LOCAL_YAML:-}"
  if [ -z "${NEXUS_DIR:-}" ] || [ "$_rai_dir" != "${NEXUS_DIR:-}" ]; then
    NEXUS_DIR="$_rai_dir"
    WORKSPACE_YAML="$_rai_dir/${RNEX_CONFIG_FILE:-rnex.yaml}"
    WORKSPACE_LOCAL_YAML="$_rai_dir/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  fi

  # Section 1: Invariant Execution Sequence Router
  cat <<'EOF'
# RNEX Workspace AI Instructions

## 1. Mandatory Execution Sequence

1. **Execution Gate**: Do NOT make any decisions, start searching across directories, or run arbitrary commands before you read and perform all instructions in this file and all files referenced by this file.
2. **Plugin Instructions**: Read and execute every mandatory plugin instruction file listed in **Section 2 (Plugin AI Instructions)** in the exact sequence specified.
3. **Repository Mode Rules**: If you are making changes or operating within member repositories, read `.rnex/repos-instructions.md` and strictly adhere to the rules for each repository according to its `Mode`.
4. **Skills**: Load a skill from `.rnex/skills/` only when its specific task applies.

## 2. Plugin AI Instructions

EOF

  # Section 2: Ordered Plugin AI Instructions
  _rai_counter=0
  _rai_seen_plugins=""
  _rai_plugin_ai_fn="${RNEX_PLUGIN_AI_FILENAME:-ai-instructions.md}"

  # Retrieve ordered active plugins (.local.rnex.yaml > rnex.yaml)
  if command -v rnex_plugins_list_ordered_active >/dev/null 2>&1; then
    _rai_ordered_plugins="$(rnex_plugins_list_ordered_active "$_rai_dir" 2>/dev/null || true)"
  elif command -v yaml_list_plugins >/dev/null 2>&1; then
    _rai_ordered_plugins="$(yaml_list_plugins 2>/dev/null || true)"
  else
    _rai_ordered_plugins=""
  fi

  for _rai_p in $_rai_ordered_plugins; do
    [ -n "$_rai_p" ] || continue

    # OWASP A03 / Path Traversal Guard: plugin identifier allowlist
    case "$_rai_p" in
      *[!a-zA-Z0-9._-]*|"") continue ;;
      .|..) continue ;;
    esac

    # Deduplicate plugin names while preserving strict configuration order
    case " $_rai_seen_plugins " in
      *" $_rai_p "*) continue ;;
    esac
    _rai_seen_plugins="${_rai_seen_plugins:+$_rai_seen_plugins }$_rai_p"

    # Filter out plugins disabled in configuration (.local.rnex.yaml > rnex.yaml)
    if command -v yaml_plugin_enabled >/dev/null 2>&1; then
      yaml_plugin_enabled "$_rai_p" 2>/dev/null || continue
    fi

    # Check whether the plugin provides an ai-instructions.md file:
    # Source plugin directory is the authoritative source of truth.
    _rai_has_ai=0
    _rai_proj_ai="$_rai_dir/.rnex/plugins/$_rai_p/$_rai_plugin_ai_fn"

    _rai_pdir=""
    if [ -d "$_rai_dir/plugins/$_rai_p" ]; then
      _rai_pdir="$_rai_dir/plugins/$_rai_p"
    elif command -v plugin_resolve_dir >/dev/null 2>&1; then
      _rai_pdir="$(plugin_resolve_dir "$_rai_p" 2>/dev/null || true)"
    fi

    if [ -n "$_rai_pdir" ] && [ -d "$_rai_pdir" ]; then
      if [ -f "$_rai_pdir/$_rai_plugin_ai_fn" ] && [ -s "$_rai_pdir/$_rai_plugin_ai_fn" ]; then
        _rai_has_ai=1
      fi
    elif [ -f "$_rai_proj_ai" ] && [ -s "$_rai_proj_ai" ]; then
      # Fallback only if source directory cannot be resolved
      _rai_has_ai=1
    fi

    # Emit mandatory numbered instruction reference when ai-instructions.md exists
    if [ "$_rai_has_ai" -eq 1 ]; then
      _rai_counter=$((_rai_counter + 1))
      printf "%d. **Mandatory**: Read and follow \`.rnex/plugins/%s/%s\`.\n" \
        "$_rai_counter" "$_rai_p" "$_rai_plugin_ai_fn"
    fi
  done

  # Invariant fallback text when no active plugins register AI instructions
  if [ "$_rai_counter" -eq 0 ]; then
    printf 'No plugin AI instructions registered.\n'
  fi

  NEXUS_DIR="$_rai_old_nexus"
  WORKSPACE_YAML="$_rai_old_wy"
  WORKSPACE_LOCAL_YAML="$_rai_old_wly"
}

# ==============================================================================
# Function: rnex_ai_generate_repos_instructions
# Responsibility: Render the markdown content for .rnex/repos-instructions.md
#                 containing the Active Member Repositories matrix (Path & Mode)
#                 and access rules.
# Architectural Layer: AI Context Layer
# Pattern: Builder / Pure Fabrication (GRASP)
# @param $1 - (Optional) Absolute or relative workspace root directory path
# @returns Outputs rendered markdown to stdout
# @pure Read-only compilation of resolved configuration state
# ==============================================================================
rnex_ai_generate_repos_instructions() {
  _ws_root="${1:-$NEXUS_DIR}"
  [ -n "$_ws_root" ] || _ws_root="${RNEX_ROOT:-.}"
  _ws_root="$(resolve_path "$_ws_root")"

  _rag_old_nd="${NEXUS_DIR:-}"
  _rag_old_wy="${WORKSPACE_YAML:-}"
  _rag_old_wly="${WORKSPACE_LOCAL_YAML:-}"

  if [ -z "${NEXUS_DIR:-}" ] || [ "$_ws_root" != "${NEXUS_DIR:-}" ]; then
    NEXUS_DIR="$_ws_root"
    WORKSPACE_YAML="$_ws_root/${RNEX_CONFIG_FILE:-rnex.yaml}"
    WORKSPACE_LOCAL_YAML="$_ws_root/${RNEX_LOCAL_CONFIG_FILE:-.local.rnex.yaml}"
  fi

  _rd="$(yaml_get_repos_dir 2>/dev/null || true)"
  [ -n "$_rd" ] || _rd="repos"
  _rd="$(clean_rel_subpath "$_rd")"

  cat <<'EOF'
# Active Member Repositories

Follow the access and modification constraints defined by each repository's `Mode` before reading or mutating files inside member repositories:

- **`read-write`** (or **`default`**): Full read and write operations are permitted within the repository path.
- **`read-only`** (or **`reference`**): Strictly read-only inspection; never modify, create, or delete files inside this repository path.

EOF

  _rows=""
  for _r in $(yaml_list_all_repos_sorted 2>/dev/null || true); do
    [ -n "$_r" ] || continue
    if ! is_enabled_val "$(yaml_get_merged_repo_field "$_r" "enabled" "true")"; then
      continue
    fi

    # Determine mode: read-only if explicitly truthy, otherwise read-write
    _mode="read-write"
    if is_truthy "$(yaml_get_merged_repo_field "$_r" "readonly" "false")"; then
      _mode="read-only"
    fi

    # Determine normalized relative repository path
    _custom_path="$(yaml_get_merged_repo_field "$_r" "path" "")"
    if [ -n "$_custom_path" ]; then
      _r_path="$(normalize_rel_path "$_custom_path")"
    else
      _r_path="${_rd}/${_r}"
    fi
    _r_path="$(clean_rel_subpath "$_r_path")"

    _rows="${_rows}| \`${_r_path}\` | \`${_mode}\` |
"
  done

  if [ -n "$_rows" ]; then
    printf '| Path | Mode |\n'
    printf '| :--- | :--- |\n'
    printf '%s' "$_rows"
  else
    printf 'No active member repositories configured.\n'
  fi

  NEXUS_DIR="$_rag_old_nd"
  WORKSPACE_YAML="$_rag_old_wy"
  WORKSPACE_LOCAL_YAML="$_rag_old_wly"
}

# ==============================================================================
# Function: rnex_ai_write_repos_instructions
# Responsibility: Compile the active member repositories table (Path & Mode only)
#                 and mode enforcement rules into .rnex/repos-instructions.md.
# Pattern: Builder / Pure Fabrication (GRASP)
# @param $1 - Absolute or relative workspace root directory path (optional)
# @returns 0 on deterministic file write, non-zero on I/O or validation failure
# @sideEffects Writes .rnex/repos-instructions.md atomically via temp file
# ==============================================================================
rnex_ai_write_repos_instructions() {
  _rawr_ws="${1:-$NEXUS_DIR}"
  [ -n "$_rawr_ws" ] || _rawr_ws="${RNEX_ROOT:-.}"
  _rawr_ws="$(resolve_path "$_rawr_ws")"
  [ -d "$_rawr_ws" ] || return 1

  _rawr_target="$_rawr_ws/${RNEX_REPOS_INSTRUCTIONS_RELPATH:-.rnex/repos-instructions.md}"
  _rawr_target_dir="$(dirname "$_rawr_target")"
  mkdir -p "$_rawr_target_dir"

  _rawr_tmp="$(mktemp "$_rawr_target_dir/.repos-instructions.XXXXXX")"
  rnex_ai_generate_repos_instructions "$_rawr_ws" > "$_rawr_tmp"

  if [ -f "$_rawr_target" ] && cmp -s "$_rawr_tmp" "$_rawr_target"; then
    rm -f "$_rawr_tmp"
  else
    mv "$_rawr_tmp" "$_rawr_target"
  fi
  return 0
}

# Compile the unified .rnex/ai-instructions.md file consumed by AI coding agents.
# Writes atomically and only replaces the file when content changes.
build_ai_instructions() {
  _dir="${1:-$NEXUS_DIR}"
  _ai_file="$_dir/${RNEX_AI_INSTRUCTIONS_RELPATH:-.rnex/ai-instructions.md}"
  mkdir -p "$(dirname "$_ai_file")"
  _out_tmp="$(mktemp "$_dir/.rnex/.ai-instructions.XXXXXX")"
  render_ai_instructions "$_dir" > "$_out_tmp"
  if [ -f "$_ai_file" ] && cmp -s "$_out_tmp" "$_ai_file"; then
    rm -f "$_out_tmp"
  else
    mv "$_out_tmp" "$_ai_file"
  fi
  rnex_ai_write_repos_instructions "$_dir"
}

# ---- Multi-Root IDE Workspace (.code-workspace) ----------------------------

# Generate and maintain a multi-root VS Code / Cursor workspace file (.code-workspace).
# Emits a deprecation warning when legacy scalar `codeWorkspace` is configured,
# resolves `enabled`, `name`, and atomic-replacement `settings` via lib/yaml.sh
# contracts, and writes valid RFC 8259 JSON atomically via a workspace temp file.
# @param $1 - Optional workspace root directory (defaults to $NEXUS_DIR).
# @returns 0 on skip or atomic update; 1 on validation, YAML, or write error.
sync_code_workspace() {
  _ws_dir="${1:-$NEXUS_DIR}"
  [ -n "$_ws_dir" ] && [ -d "$_ws_dir" ] || return 0

  # 1. Surface legacy scalar deprecation notice once at the sync boundary
  if rnex_is_legacy_code_workspace "$_ws_dir"; then
    log_warn "Deprecated: scalar 'codeWorkspace' is deprecated; use 'codeWorkspace: { enabled: true|false }' instead."
  fi

  # 2. Skip cleanly when codeWorkspace is disabled
  if ! rnex_get_code_workspace_enabled "$_ws_dir"; then
    return 0
  fi

  # 3. Resolve and validate target .code-workspace filename
  _raw_name="$(rnex_get_code_workspace_name "$_ws_dir")" || return 1
  _root_name="$(basename "$_ws_dir")"
  if [ -n "$_raw_name" ]; then
    _cw_file="$(rnex_normalize_workspace_filename "$_raw_name")" || return 1
  else
    _cw_file="${_root_name}${RNEX_CODE_WORKSPACE_EXT:-.code-workspace}"
  fi

  # 4. Resolve settings JSON (atomic replacement; fail-fast before any disk write)
  _settings_json="$(rnex_get_code_workspace_settings_json "$_ws_dir")" || return 1

  CODE_WORKSPACE_FILE="$_cw_file"
  _ws_path="$_ws_dir/$_cw_file"
  _repos_rel="${REPOS_DIR#"$_ws_dir"/}"
  _repos_rel="${_repos_rel#./}"
  [ -n "$_repos_rel" ] || _repos_rel="repos"

  # 5. Render strict RFC 8259 JSON to an in-workspace temp file and atomically mv
  mkdir -p "$_ws_dir/.rnex" || return 1
  _cw_tmp="$_ws_dir/.rnex/.tmp.code-workspace.$$"
  rm -f "$_cw_tmp"
  _existed=0
  [ -f "$_ws_path" ] && _existed=1

  _root_esc="$(printf '%s' "$_root_name" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  if ! {
    printf '{\n  "folders": [\n'
    printf '    {\n      "name": "%s (Workspace Root)",\n      "path": "."\n    }' "$_root_esc"

    yaml_list_repos | while IFS= read -r _rname || [ -n "$_rname" ]; do
      [ -n "$_rname" ] || continue
      if yaml_repo_enabled "$_rname"; then
        _rdir="$(resolve_repo_path "$_rname")"
        if [ -d "$_rdir" ]; then
          _custom_p="$(yaml_get "$_rname" "path" 2>/dev/null || true)"
          if [ -n "$_custom_p" ]; then
            _folder_p="$(clean_rel_subpath "$_custom_p")"
          else
            _folder_p="$_repos_rel/$_rname"
          fi
          _rn_esc="$(printf '%s' "$_rname" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
          _fp_esc="$(printf '%s' "$_folder_p" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
          printf ',\n    {\n      "name": "%s",\n      "path": "%s"\n    }' "$_rn_esc" "$_fp_esc"
        fi
      fi
    done

    printf '\n  ],\n'
    printf '%s\n' "$_settings_json" | awk '
      NR == 1 { print "  \"settings\": " $0; next }
      { print "  " $0 }
    '
    printf '}\n'
  } > "$_cw_tmp"; then
    rm -f "$_cw_tmp"
    return 1
  fi

  if [ "$_existed" -eq 1 ]; then
    if cmp -s "$_cw_tmp" "$_ws_path"; then
      rm -f "$_cw_tmp"
    else
      mv "$_cw_tmp" "$_ws_path" || { rm -f "$_cw_tmp"; return 1; }
    fi
    log_ok "Updated $_cw_file"
  else
    mv "$_cw_tmp" "$_ws_path" || { rm -f "$_cw_tmp"; return 1; }
    log_ok "Created $_cw_file (VS Code / Cursor multi-root workspace)"
  fi
}

# ---- Provider Skill Directory & Base Asset Synchronization -----------------

write_rnex_env_script() {
  _dir="${1:-$NEXUS_DIR}"
  _bin_dir="$_dir/.rnex/bin"
  mkdir -p "$_bin_dir"
  _env_script="$_bin_dir/rnex-env.sh"
  _src_env=""
  for _cand in \
    "${RNEX_LIB_DIR:-}/rnex-env.sh" \
    "$SCRIPT_LOCATION/lib/rnex-env.sh" \
    "$(dirname "$SCRIPT_LOCATION")/lib/rnex-env.sh" \
    "$_dir/lib/rnex-env.sh" \
    "${RNEX_LIB_DIR:-}/sdk.sh" \
    "$SCRIPT_LOCATION/lib/sdk.sh" \
    "$(dirname "$SCRIPT_LOCATION")/lib/sdk.sh" \
    "$_dir/lib/sdk.sh"; do
    if [ -n "$_cand" ] && [ -f "$_cand" ]; then
      _src_env="$_cand"
      break
    fi
  done
  if [ -n "$_src_env" ]; then
    cp "$_src_env" "$_env_script"
    # Materialize root-level .rnex/rnex-env.sh for backward-compatibility with callers
    cp "$_src_env" "$_dir/.rnex/rnex-env.sh"
    chmod +x "$_dir/.rnex/rnex-env.sh" 2>/dev/null || true
  fi
  chmod +x "$_env_script" 2>/dev/null || true
}

get_active_provider_skill_dirs() {
  _dirs=""
  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    yaml_plugin_enabled "$_p" 2>/dev/null || continue
    if provider_option_enabled "$_p" "skills" 2>/dev/null; then
      _sdir="$(plugin_get_skill_dir "$_p")"
      if [ -n "$_sdir" ]; then
        case " $_dirs " in
          *" $_sdir "*) ;;
          *) _dirs="${_dirs:+$_dirs }$_sdir" ;;
        esac
      fi
    fi
  done
  printf '%s' "$_dirs"
}

# Synchronize built-in core agentic skills into .rnex/skills/ and register
# zero-logic user skill pointers across all active AI assistant directories.
sync_rnex_base_assets() {
  _src_skills=""
  if [ -n "${RNEX_SKILLS_DIR:-}" ] && [ -d "$RNEX_SKILLS_DIR" ]; then
    _src_skills="$RNEX_SKILLS_DIR"
  elif [ -n "${SKILLS_DIR:-}" ] && [ -d "$SKILLS_DIR" ]; then
    _src_skills="$SKILLS_DIR"
  elif [ -d "$SCRIPT_LOCATION/skills" ]; then
    _src_skills="$SCRIPT_LOCATION/skills"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/skills" ]; then
    _src_skills="$(dirname "$SCRIPT_LOCATION")/skills"
  elif [ -d "$NEXUS_DIR/skills" ]; then
    _src_skills="$NEXUS_DIR/skills"
  elif [ -d "${RNEX_ROOT:-}/skills" ]; then
    _src_skills="${RNEX_ROOT:-}/skills"
  fi

  # Ensure .rnex/skills exists
  mkdir -p "$NEXUS_DIR/.rnex/skills"

  # Clean old skill subdirectories if any exist in .rnex/skills/
  for _item in "$NEXUS_DIR/.rnex/skills"/*; do
    [ -e "$_item" ] || continue
    [ -d "$_item" ] && rm -rf "${_item:?}"
  done

  # Sync base skills to .rnex/skills/
  if [ -n "$_src_skills" ] && [ -d "$_src_skills" ]; then
    cp -f "$_src_skills"/*.md "$NEXUS_DIR/.rnex/skills/" 2>/dev/null || true
  fi

  # Purge any plugin-declared skills that may have been placed in core .rnex/skills/
  _active_prov_skill_dirs="$(get_active_provider_skill_dirs 2>/dev/null || true)"
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    if [ -d "$_pdir/skills" ]; then
      for _psk in "$_pdir/skills"/*.md; do
        [ -f "$_psk" ] || continue
        _sbase="$(basename "$_psk")"
        _sname="$(basename "$_psk" .md)"
        rm -f "$NEXUS_DIR/.rnex/skills/$_sbase" "$NEXUS_DIR/.rnex/skills/rnex-$_sbase" 2>/dev/null || true
        for _p_dir in $_active_prov_skill_dirs; do
          rm -f "$NEXUS_DIR/$_p_dir/rnex-$_sbase" 2>/dev/null || true
          rm -rf "${NEXUS_DIR:?}/${_p_dir:?}/rnex-${_sname:?}" 2>/dev/null || true
        done
      done
    fi
  done

  # Register core User Skills across active provider directories
  for _sk_file in "$NEXUS_DIR/.rnex/skills"/*.md; do
    [ -f "$_sk_file" ] || continue
    _sk_name="$(basename "$_sk_file" .md)"
    rnex_register_user_skill "$_sk_name" ".rnex/skills/${_sk_name}.md"
  done
}

sync_skills() {
  write_rnex_env_script "$NEXUS_DIR"
  sync_rnex_base_assets
}
