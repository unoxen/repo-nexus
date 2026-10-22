#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/ai.sh — Workspace AI context, .gitignore/.ignore, and skill orchestration
# ============================================================================

# ---- Gitignore & Search Tool Ignore Reconciliation -------------------------

reconcile_gitignore() {
  _dir="${1:-$NEXUS_DIR}"
  _gi="$_dir/.gitignore"

  if [ ! -f "$_gi" ]; then
    cat > "$_gi" <<GI_EOF
# Member repos (managed by rnex, ignored at workspace level)
repos/*
!repos/.gitkeep

# Local machine-specific configuration
$RNEX_LOCAL_CONFIG_FILE
.rnex.local.yaml
GI_EOF
    log_ok "Created .gitignore (ignoring repos/ and $RNEX_LOCAL_CONFIG_FILE)"
  else
    # 1. Strip any legacy lint_trigger_counter entries if present
    if grep -q "lint_trigger_counter" "$_gi" 2>/dev/null; then
      _tmp="$(mktemp)"
      grep -v "lint_trigger_counter" "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      log_ok "Removed legacy lint trigger counter entries from .gitignore"
    fi

    # 2. Strip legacy .rnex/ entries if present (.rnex/ contains tracked plugins, skills, and hooks)
    if grep -qE '^[ ]*#?[ ]*Repo Nexus internal state' "$_gi" 2>/dev/null || grep -qE '^\.rnex/?$' "$_gi" 2>/dev/null; then
      _tmp="$(mktemp)"
      grep -vE '(^[ ]*#?[ ]*Repo Nexus internal state|^\.rnex/?$)' "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
      log_ok "Removed .rnex/ from .gitignore (.rnex should be tracked in git)"
    fi

    # 3. Ensure repos/* is ignored
    if ! grep -q "^repos" "$_gi" 2>/dev/null; then
      printf '\n# Member repos (managed by rnex)\nrepos/*\n!repos/.gitkeep\n' >> "$_gi"
      log_dim "Added repos/* to .gitignore"
    fi

    # 4. Ensure local config files are ignored
    if ! grep -qF "$RNEX_LOCAL_CONFIG_FILE" "$_gi" 2>/dev/null; then
      printf '\n# Local machine-specific configuration\n%s\n' "$RNEX_LOCAL_CONFIG_FILE" >> "$_gi"
      log_dim "Added $RNEX_LOCAL_CONFIG_FILE to .gitignore"
    fi
    if ! grep -qF ".rnex.local.yaml" "$_gi" 2>/dev/null; then
      printf '.rnex.local.yaml\n' >> "$_gi"
    fi
  fi

  # Universal search tool ignore file (ripgrep, Claude Code, VS Code, Zed)
  ensure_provider_ignore "$_dir/.ignore" \
    "Member repos (un-ignored for ripgrep, Claude Code, VS Code, and search tools)" \
    "Created .ignore (un-ignoring member repos for search tools)"
}

# ---- AI Instructions Compilation (.rnex/ai-instructions.md) ----------------

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
Each member repository is an autonomous Git repository. For repository-specific instructions, inspect `repos/<name>/.rnex/`. Inspect only targeted files required for the task.

## Workspace Maintenance
When workspace configuration, routing blocks, plugin assets, or member repository structures require reconciliation or schema upgrades:
- Run `rnex sync` (or `rnex status` to check workspace health).
- Use `rnex sync -y` to non-destructively apply configuration version upgrades automatically.

## Git Operations
Commit and push changes directly within the respective member repository root (`repos/<name>/`).
BASE_AI_EOF
  fi

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
      _pdir="$(find_plugin_dir "$_p" 2>/dev/null || true)"
      _sdir=""
      if [ -n "$_pdir" ]; then
        _sdir="$(plugin_get_field "$_pdir" "skill_dir" 2>/dev/null || true)"
      fi
      if [ -z "$_sdir" ]; then
        case "$_p" in
          copilot)  _sdir=".github/skills" ;;
          cursor)   _sdir=".cursor/rules" ;;
          claude)   _sdir=".claude/skills" ;;
          windsurf) _sdir=".windsurf/rules" ;;
          gemini)   _sdir=".agents/skills" ;;
        esac
      fi
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
