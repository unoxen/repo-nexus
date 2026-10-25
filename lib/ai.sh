#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/ai.sh — Workspace AI context, .gitignore/.ignore, and skill orchestration
# ============================================================================

# ---- Gitignore & Search Tool Ignore Reconciliation -------------------------

GITIGNORE_MARKER_START="# REPO-NEXUS:START"
GITIGNORE_MARKER_END="# REPO-NEXUS:END"

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

# Recursive Repo Nexus directories (trailing slashes prevent ignoring rnex executable or rnex.yaml)
**/.rnex*/
**/rnex*/
.rnex*/
rnex*/

# Local machine-specific configuration
$RNEX_LOCAL_CONFIG_FILE
.rnex.local.yaml
GI_SECTION_EOF

  _custom_ignores="$(yaml_get_git_ignore 2>/dev/null || true)"
  if [ -n "$_custom_ignores" ]; then
    _added_custom_header=0
    _seen_custom=""
    printf '%s\n' "$_custom_ignores" | while IFS= read -r _ci || [ -n "$_ci" ]; do
      [ -n "$_ci" ] || continue
      case "$_ci" in
        "repos/"|"repos/*"|"!repos/.gitkeep"|"${_active_repos_dir}/"|"${_active_repos_dir}/*"|"!${_active_repos_dir}/.gitkeep"|"**/.rnex*/"|"**/rnex*/"|".rnex*/"|"rnex*/"|"$RNEX_LOCAL_CONFIG_FILE"|".rnex.local.yaml")
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
    # 1. Strip any legacy lint_trigger_counter entries if present
    if grep -q "lint_trigger_counter" "$_gi" 2>/dev/null; then
      _tmp="$(mktemp)"
      grep -v "lint_trigger_counter" "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      log_ok "Removed legacy lint trigger counter entries from .gitignore"
    fi

    # 2. If delimited section exists, replace it in-place with the newly synced section
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
      # 3. Upgrade legacy un-delimited .gitignore or append managed section to existing user .gitignore
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
        $0 == ".rnex" || $0 == "rnex" { next }
        $0 == local_cfg || $0 == ".rnex.local.yaml" { next }
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

# Clean managed Repo Nexus ignore block from .gitignore, removing file if empty
clean_rnex_gitignore() {
  _dir="${1:-$NEXUS_DIR}"
  _gi="$_dir/.gitignore"
  [ -f "$_gi" ] || return 0
  if grep -qFx -- "${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" "$_gi" 2>/dev/null; then
    _user_content="$(awk -v s="${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${GITIGNORE_MARKER_END:-# REPO-NEXUS:END}" '
      $0 == s { in_b = 1; next }
      $0 == e { in_b = 0; next }
      !in_b { print }
    ' "$_gi" | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d')"
    if [ -z "$_user_content" ]; then
      rm -f "$_gi"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed .gitignore"
    else
      _tmp="$(mktemp)"
      awk -v s="${GITIGNORE_MARKER_START:-# REPO-NEXUS:START}" -v e="${GITIGNORE_MARKER_END:-# REPO-NEXUS:END}" '
        $0 == s { in_b = 1; next }
        $0 == e { in_b = 0; next }
        !in_b { print }
      ' "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      [ "${RNEX_QUIET:-0}" -eq 0 ] && [ "${_sync_quiet:-0}" -eq 0 ] && log_ok "Removed Repo Nexus rules from .gitignore"
    fi
  fi
}

# ---- AI Instructions Compilation (.rnex/ai-instructions.md) ----------------

# Resolve the primary instruction file for an AI provider plugin
plugin_get_instruction_file() {
  _pif_name="$1"
  _pif_pdir="${2:-}"
  [ -n "$_pif_pdir" ] || _pif_pdir="$(find_plugin_dir "$_pif_name" 2>/dev/null || true)"
  _pif_file=""
  if [ -n "$_pif_pdir" ]; then
    _pif_file="$(plugin_get_field "$_pif_pdir" "instruction_file" 2>/dev/null || true)"
  fi
  if [ -z "$_pif_file" ]; then
    case "$_pif_name" in
      claude)   _pif_file="CLAUDE.md" ;;
      gemini)   _pif_file="GEMINI.md" ;;
      cursor)   _pif_file=".cursorrules" ;;
      windsurf) _pif_file=".windsurfrules" ;;
      codex)    _pif_file="CODEX.md" ;;
      copilot)  _pif_file=".github/copilot-instructions.md" ;;
      agents|agent) _pif_file="AGENTS.md" ;;
    esac
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

# Check if an instruction file contains custom user instructions outside the rnex block
file_has_user_content() {
  _fhuc_file="$1"
  [ -f "$_fhuc_file" ] || return 1
  _content=""
  if grep -qF "${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}" "$_fhuc_file" 2>/dev/null; then
    _content="$(awk -v s="${AI_MARKER_START:-<!-- REPO-NEXUS:START -->}" -v e="${AI_MARKER_END:-<!-- REPO-NEXUS:END -->}" '
      $0 == s { in_b = 1; next }
      $0 == e { in_b = 0; next }
      !in_b { print }
    ' "$_fhuc_file" | sed -e '/^[[:space:]]*$/d')"
  else
    _content="$(grep -v "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_fhuc_file" 2>/dev/null | grep -v "Multi-Repo AI Workspace Context" | sed -e '/^[[:space:]]*$/d')"
  fi
  [ -n "$_content" ]
}

# Reconcile AI provider instruction files:
# - When provider plugins are enabled (e.g. Gemini, Claude), creates/updates their specific instruction files (GEMINI.md, CLAUDE.md)
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

  # For any existing instruction files on disk that are NOT currently active:
  # Clean rnex instructions (removing file if empty outside block, or stripping rnex block)
  for _if in CLAUDE.md GEMINI.md CODEX.md .cursorrules .windsurfrules .github/copilot-instructions.md; do
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

# Compile the unified .rnex/ai-instructions.md file consumed by AI coding agents.
# Aggregates sample template instructions and active plugin instruction sections.
build_ai_instructions() {
  _dir="${1:-$NEXUS_DIR}"
  _ai_file="$_dir/.rnex/ai-instructions.md"
  mkdir -p "$_dir/.rnex"

  _tmpl_file=""
  for _cand in \
    "$_dir/templates/ai-instructions.sample.md" \
    "$SCRIPT_LOCATION/templates/ai-instructions.sample.md" \
    "$(dirname "$SCRIPT_LOCATION")/templates/ai-instructions.sample.md"; do
    if [ -f "$_cand" ]; then
      _tmpl_file="$_cand"
      break
    fi
  done

  _out_tmp="$(mktemp)"
  if [ -n "$_tmpl_file" ]; then
    cat "$_tmpl_file" > "$_out_tmp"
  else
    cat > "$_out_tmp" <<'BASE_AI_EOF'
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

### Mandatory Session Startup
Execute in sequence before task execution:
1. **Read Configuration First (Highest Priority)**: Read `.local.rnex.yaml` (if present) and `rnex.yaml` to identify active member repositories (`repos/`) and enabled plugins.
2. **Plugin & Skill Routing**: Inspect active plugin instructions under `.rnex/plugins/<plugin-name>/`, and core agentic skills under `.rnex/skills/` when relevant.
3. **Targeted Member Repository Access Only**: Navigate directly to specific files in `repos/<name>/` relevant to the user request. Avoid blind repository-wide scans or unbounded searches across `repos/`.

## Subagents
Autonomous subagents are defined under `.rnex/agents/` and active plugin agents under `.rnex/plugins/<plugin-name>/agents/`.

## Member Repositories (`repos/<name>/`)
Each member repository is an autonomous Git repository. Inspect only targeted files required for the task.
If repository-specific context exists, it is stored under `repos/<name>/.rnex/`.
Repositories marked `readonly: true` in configuration are reference-only: DO NOT modify, write to, or commit changes in read-only repositories; use them strictly for information, code exploration, and schema references.

## Workspace Maintenance
When workspace configuration, routing blocks, plugin assets, or member repository structures require reconciliation or schema upgrades:
- Run `rnex sync` (or `rnex status` to check workspace health).
- Use `rnex sync -y` to non-destructively apply configuration version upgrades automatically.

## Git Operations
Commit and push changes directly within the respective member repository root (`repos/<name>/`). For read-only repositories (`readonly: true`), never commit, edit, or push changes.
BASE_AI_EOF
  fi

  _active_rd="$(yaml_get_repos_dir 2>/dev/null || printf 'repos')"
  [ -n "$_active_rd" ] || _active_rd="repos"
  sed -e "s#\${REPOS_DIR_REL:-repos}#${_active_rd}#g" \
      -e "s#\${REPOS_DIR_REL}#${_active_rd}#g" \
      -e "s#\./repos/#./${_active_rd}/#g" \
      -e "s#\`repos/#\`${_active_rd}/#g" \
      -e "s#repos/<name>#${_active_rd}/<name>#g" \
      -e "s#repos/\`#${_active_rd}/\`#g" \
      "$_out_tmp" > "${_out_tmp}.subst" && mv "${_out_tmp}.subst" "$_out_tmp"

  for _p in $(yaml_list_plugins 2>/dev/null || true); do
    [ -n "$_p" ] || continue
    yaml_plugin_enabled "$_p" 2>/dev/null || continue
    _pdir="$(find_plugin_dir "$_p" 2>/dev/null || true)"
    _p_instr_files=""
    if [ -n "$_pdir" ] && [ -f "$_pdir/plugin.yaml" ]; then
      for _item in $(plugin_list_instructions "$_pdir" 2>/dev/null || true); do
        [ -n "$_item" ] || continue
        _src="${_item%%:*}"
        _src="$(printf '%s' "$_src" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        _found=""
        if [ -f "$_dir/.rnex/plugins/$_p/$_src" ]; then
          _found="$_dir/.rnex/plugins/$_p/$_src"
        elif [ -f "$_pdir/$_src" ]; then
          _found="$_pdir/$_src"
        fi
        if [ -n "$_found" ]; then
          _p_instr_files="${_p_instr_files:+$_p_instr_files }$_found"
        fi
      done
    fi

    if [ -z "$_p_instr_files" ]; then
      if [ -f "$_dir/.rnex/plugins/$_p/instructions.md" ]; then
        _p_instr_files="$_dir/.rnex/plugins/$_p/instructions.md"
      elif [ -n "$_pdir" ] && [ -f "$_pdir/instructions.md" ]; then
        _p_instr_files="$_pdir/instructions.md"
      fi
    fi

    for _f in $_p_instr_files; do
      printf '\n\n' >> "$_out_tmp"
      cat "$_f" >> "$_out_tmp"
    done
  done

  mv "$_out_tmp" "$_ai_file"
}

# ---- Multi-Root IDE Workspace (.code-workspace) ----------------------------

# Generate and maintain a multi-root VS Code / Cursor workspace file (.code-workspace).
# Adds workspace root and each active member repository as first-class workspace folders.
sync_code_workspace() {
  [ -n "$CODE_WORKSPACE_FILE" ] || return 0
  _ws_path="$NEXUS_DIR/$CODE_WORKSPACE_FILE"
  _root_name="$(basename "$NEXUS_DIR")"

  _f_tmp="$(mktemp)"

  printf '    {\n      "name": "%s (Workspace Root)",\n      "path": "."\n    }' "$_root_name" > "$_f_tmp"

  _repos_rel="${REPOS_DIR#"$NEXUS_DIR"/}"
  _repos_rel="${_repos_rel#./}"
  [ -n "$_repos_rel" ] || _repos_rel="repos"

  yaml_list_repos | while read -r _rname; do
    [ -n "$_rname" ] || continue
    if yaml_repo_enabled "$_rname"; then
      _rdir="$(resolve_repo_path "$_rname")"
      if [ -d "$_rdir" ]; then
        printf ',\n    {\n      "name": "%s",\n      "path": "%s/%s"\n    }' "$_rname" "$_repos_rel" "$_rname" >> "$_f_tmp"
      fi
    fi
  done

  if [ ! -f "$_ws_path" ]; then
    {
      printf '{\n  "folders": [\n'
      cat "$_f_tmp"
      printf '\n  ],\n  "settings": {\n    "search.exclude": {\n      "**/node_modules": true,\n      "**/.git": true\n    }\n  }\n}\n'
    } > "$_ws_path"
    rm -f "$_f_tmp"
    log_ok "Created $CODE_WORKSPACE_FILE (VS Code / Cursor multi-root workspace)"
    return 0
  fi

  if grep -q '"folders"[ ]*:' "$_ws_path" 2>/dev/null; then
    _tmp_out="$(mktemp)"
    awk -v f_src="$_f_tmp" '
      BEGIN { in_f = 0 }
      /"folders"[ ]*:[ ]*\[/ {
        in_f = 1
        print "  \"folders\": ["
        while ((getline line < f_src) > 0) print line
        close(f_src)
        next
      }
      in_f {
        if (/\]/) {
          in_f = 0
          has_comma = ($0 ~ /,[ ]*$/) ? "," : ""
          print "  ]" has_comma
        }
        next
      }
      { print }
    ' "$_ws_path" > "$_tmp_out" && mv "$_tmp_out" "$_ws_path"
    rm -f "$_f_tmp"
    log_ok "Updated folders in $CODE_WORKSPACE_FILE"
  else
    {
      printf '{\n  "folders": [\n'
      cat "$_f_tmp"
      printf '\n  ],\n  "settings": {\n    "search.exclude": {\n      "**/node_modules": true,\n      "**/.git": true\n    }\n  }\n}\n'
    } > "$_ws_path"
    rm -f "$_f_tmp"
    log_ok "Updated $CODE_WORKSPACE_FILE"
  fi
}

# ---- Provider Skill Directory & Base Asset Synchronization -----------------

write_rnex_env_script() {
  _dir="${1:-$NEXUS_DIR}"
  _bin_dir="$_dir/.rnex/bin"
  mkdir -p "$_bin_dir"
  _env_script="$_bin_dir/rnex-env.sh"
  _src_sdk=""
  for _cand in \
    "${RNEX_LIB_DIR:-}/sdk.sh" \
    "$SCRIPT_LOCATION/lib/sdk.sh" \
    "$(dirname "$SCRIPT_LOCATION")/lib/sdk.sh" \
    "$_dir/lib/sdk.sh"; do
    if [ -n "$_cand" ] && [ -f "$_cand" ]; then
      _src_sdk="$_cand"
      break
    fi
  done
  if [ -n "$_src_sdk" ]; then
    cp "$_src_sdk" "$_env_script"
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
  _src_toolkit=""
  if [ -d "$SCRIPT_LOCATION/toolkit" ]; then
    _src_toolkit="$SCRIPT_LOCATION/toolkit"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit" ]; then
    _src_toolkit="$(dirname "$SCRIPT_LOCATION")/toolkit"
  elif [ -d "$NEXUS_DIR/toolkit" ]; then
    _src_toolkit="$NEXUS_DIR/toolkit"
  fi

  # Purge obsolete .rnex/prompts/ and .rnex/workflows/
  rm -rf "$NEXUS_DIR/.rnex/prompts" "$NEXUS_DIR/.rnex/workflows" 2>/dev/null || true

  # Ensure .rnex/skills exists
  mkdir -p "$NEXUS_DIR/.rnex/skills"

  # Clean old skill subdirectories if any exist in .rnex/skills/
  for _item in "$NEXUS_DIR/.rnex/skills"/*; do
    [ -e "$_item" ] || continue
    [ -d "$_item" ] && rm -rf "$_item"
  done

  # Sync base skills to .rnex/skills/
  if [ -n "$_src_toolkit" ] && [ -d "$_src_toolkit/skills" ]; then
    cp -f "$_src_toolkit"/skills/*.md "$NEXUS_DIR/.rnex/skills/" 2>/dev/null || true
  fi

  # Purge any plugin-declared skills that may have been placed in core .rnex/skills/
  for _pdir in $(list_all_available_plugin_dirs 2>/dev/null || true); do
    if [ -d "$_pdir/skills" ]; then
      for _psk in "$_pdir/skills"/*.md; do
        [ -f "$_psk" ] || continue
        _sbase="$(basename "$_psk")"
        _sname="$(basename "$_psk" .md)"
        rm -f "$NEXUS_DIR/.rnex/skills/$_sbase" "$NEXUS_DIR/.rnex/skills/rnex-$_sbase" 2>/dev/null || true
        for _p_dir in $(get_active_provider_skill_dirs 2>/dev/null || true); do
          rm -f "$NEXUS_DIR/$_p_dir/rnex-$_sbase" 2>/dev/null || true
          rm -rf "$NEXUS_DIR/$_p_dir/rnex-$_sname" 2>/dev/null || true
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
