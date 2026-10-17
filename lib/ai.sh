#!/bin/sh
# shellcheck shell=sh
# ============================================================================
# lib/ai.sh — AI Instructions, workspace context, and AI provider synchronization
# ============================================================================

# ---- AI Instructions Management (Routing-Only) ----------------------------

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
    return 0
  fi

  # 1. Strip any legacy lint_trigger_counter entries if present
  if grep -q "lint_trigger_counter" "$_gi" 2>/dev/null; then
    _tmp="$(mktemp)"
    grep -v "lint_trigger_counter" "$_gi" > "$_tmp" && mv "$_tmp" "$_gi"
    log_ok "Removed legacy lint trigger counter entries from .gitignore"
  fi

  # 2. Strip legacy .rnex/ entries if present (.rnex/ contains tracked prompts, plugins, and hooks)
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

  # Universal search tool ignore file (ripgrep, Claude Code, VS Code, Zed)
  # Un-ignores member repositories for search tools while Git continues to ignore them
  _ign="$_dir/.ignore"
  if [ ! -f "$_ign" ]; then
    cat > "$_ign" <<IGN_EOF
# Member repos (un-ignored for ripgrep, Claude Code, VS Code, and search tools)
!repos/*
IGN_EOF
    log_ok "Created .ignore (un-ignoring member repos for search tools)"
  elif ! grep -q '!repos/\*' "$_ign" 2>/dev/null; then
    printf '\n# Member repos (un-ignored for search tools)\n!repos/*\n' >> "$_ign"
    log_dim "Added !repos/* to .ignore"
  fi
}

# ---- AI Instructions Management (Routing-Only) ----------------------------

AI_MARKER_START="<!-- REPO-NEXUS:START -->"
AI_MARKER_END="<!-- REPO-NEXUS:END -->"

get_rnex_instructions() {
  printf "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\` before executing any task or answering any query in this workspace.\n"
}

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
    _p_instr=""
    if [ -f "$_dir/.rnex/plugins/$_p/instructions.md" ]; then
      _p_instr="$_dir/.rnex/plugins/$_p/instructions.md"
    elif [ -n "$_pdir" ] && [ -f "$_pdir/instructions.md" ]; then
      _p_instr="$_pdir/instructions.md"
    fi

    if [ -n "$_p_instr" ]; then
      printf '\n\n' >> "$_out_tmp"
      cat "$_p_instr" >> "$_out_tmp"
    fi
  done

  mv "$_out_tmp" "$_ai_file"
}

merge_rnex_instructions() {
  _dst="$1"
  _body_tmp="$(mktemp)"
  get_rnex_instructions > "$_body_tmp"

  if [ ! -f "$_dst" ]; then
    mkdir -p "$(dirname "$_dst")"
    {
      printf '%s\n' "$AI_MARKER_START"
      cat "$_body_tmp"
      printf '%s\n' "$AI_MARKER_END"
    } > "$_dst"
    rm -f "$_body_tmp"
    log_ok "Created $(basename "$_dst") with Repo Nexus routing instructions"
    return 0
  fi

  if grep -q "CRITICAL: You MUST read and strictly follow all instructions in \`.rnex/ai-instructions.md\`" "$_dst" 2>/dev/null && ! grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    {
      printf '%s\n' "$AI_MARKER_START"
      cat "$_body_tmp"
      printf '%s\n' "$AI_MARKER_END"
    } > "$_dst"
    rm -f "$_body_tmp"
    return 0
  fi

  # Case 1: If delimiters already exist, update the block in-place
  if grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" -v src="$_body_tmp" '
      $0 == s {
        in_b = 1
        print s
        while ((getline line < src) > 0) print line
        close(src)
        next
      }
      $0 == e {
        in_b = 0
        print e
        next
      }
      !in_b { print }
    ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
    rm -f "$_body_tmp"
    log_ok "Updated Repo Nexus routing instructions in $(basename "$_dst")"
    return 0
  fi

  # Case 2: If no delimiters, check for legacy un-delimited Repo Nexus block
  # (e.g. starting with "# Multi-Repo AI Workspace Context" or containing "Symlink Write-Through")
  if grep -q "Multi-Repo AI Workspace Context" "$_dst" 2>/dev/null || grep -q "Symlink Write-Through" "$_dst" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" -v src="$_body_tmp" '
      BEGIN { in_legacy = 0; replaced = 0 }
      /^# Multi-Repo AI Workspace Context/ {
        in_legacy = 1
        if (!replaced) {
          print s
          while ((getline line < src) > 0) print line
          close(src)
          print e
          replaced = 1
        }
        next
      }
      in_legacy {
        if (/^# [^#]/ && !/^# Multi-Repo/) {
          in_legacy = 0
          print
          next
        }
        next
      }
      !in_legacy { print }
      END {
        if (!replaced) {
          print s
          while ((getline line < src) > 0) print line
          close(src)
          print e
        }
      }
    ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
    rm -f "$_body_tmp"
    log_ok "Upgraded legacy instructions to Repo Nexus routing block in $(basename "$_dst")"
    return 0
  fi

  # Case 3: Completely custom instructions file without rnex context — append delimited block
  _tmp="$(mktemp)"
  cp "$_dst" "$_tmp"
  if [ -s "$_tmp" ] && [ -n "$(tail -c 1 "$_tmp" 2>/dev/null)" ]; then
    printf '\n' >> "$_tmp"
  fi
  {
    printf '\n%s\n' "$AI_MARKER_START"
    cat "$_body_tmp"
    printf '\n%s\n' "$AI_MARKER_END"
  } >> "$_tmp"
  mv "$_tmp" "$_dst"
  rm -f "$_body_tmp"
  log_ok "Merged Repo Nexus routing instructions with existing $(basename "$_dst")"
}

clean_rnex_instructions() {
  _dst="$1"
  [ -f "$_dst" ] || return 0
  if grep -qF "$AI_MARKER_START" "$_dst" 2>/dev/null; then
    _non_rnex="$(awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$_dst" | tr -d " \t\r\n")"
    if [ -z "$_non_rnex" ]; then
      rm -f "$_dst"
      log_ok "Removed $(basename "$_dst")"
    else
      _tmp="$(mktemp)"
      awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" '
        $0 == s { skip=1; next }
        $0 == e { skip=0; next }
        !skip { print }
      ' "$_dst" > "$_tmp" && mv "$_tmp" "$_dst"
      log_ok "Removed Repo Nexus routing instructions from $(basename "$_dst")"
    fi
  fi
}

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

# ---- Provider Skill Directory & User Skill Generator API -------------------

write_rnex_env_script() {
  _dir="${1:-$NEXUS_DIR}"
  _bin_dir="$_dir/.rnex/bin"
  mkdir -p "$_bin_dir"
  _env_script="$_bin_dir/rnex-env.sh"
  _tmpl_env=""
  for _cand in \
    "$_dir/templates/rnex-env.sh" \
    "$SCRIPT_LOCATION/templates/rnex-env.sh" \
    "$(dirname "$SCRIPT_LOCATION")/templates/rnex-env.sh" \
    "${RNEX_LIB_DIR:-}/../templates/rnex-env.sh" \
    "./templates/rnex-env.sh"; do
    if [ -f "$_cand" ]; then
      _tmpl_env="$_cand"
      break
    fi
  done
  if [ -n "$_tmpl_env" ]; then
    cp "$_tmpl_env" "$_env_script"
  fi
  chmod +x "$_env_script" 2>/dev/null || true
}

get_active_provider_skill_dirs() {
  _dirs=""
  if provider_option_enabled "copilot" "skills" 2>/dev/null; then
    _dirs="${_dirs:+$_dirs }.github/skills"
  fi
  if provider_option_enabled "cursor" "skills" 2>/dev/null; then
    _dirs="${_dirs:+$_dirs }.cursor/rules"
  fi
  if provider_option_enabled "claude" "skills" 2>/dev/null; then
    _dirs="${_dirs:+$_dirs }.claude/skills"
  fi
  if provider_option_enabled "windsurf" "skills" 2>/dev/null; then
    _dirs="${_dirs:+$_dirs }.windsurf/rules"
  fi
  if provider_option_enabled "gemini" "skills" 2>/dev/null; then
    _dirs="${_dirs:+$_dirs }.gemini/skills"
  fi
  printf '%s' "$_dirs"
}

_tmpl_env=""
for _cand in \
  "$SCRIPT_LOCATION/templates/rnex-env.sh" \
  "$(dirname "$SCRIPT_LOCATION")/templates/rnex-env.sh" \
  "${RNEX_LIB_DIR:-}/../templates/rnex-env.sh" \
  "./templates/rnex-env.sh"; do
  if [ -f "$_cand" ]; then
    _tmpl_env="$_cand"
    break
  fi
done
if [ -n "$_tmpl_env" ]; then
  # shellcheck source=/dev/null
  . "$_tmpl_env"
fi

clean_provider_user_skills() {
  _sk_dir="$1"
  [ -d "$_sk_dir" ] || return 0
  rm -f "$_sk_dir"/rnex-*.md 2>/dev/null || true
  for _d in "$_sk_dir"/rnex-*; do
    [ -d "$_d" ] || continue
    rm -rf "$_d" 2>/dev/null || true
  done
  rmdir "$_sk_dir" 2>/dev/null || true
}

clean_plugin_user_skills() {
  _pdir="$1"
  [ -d "$_pdir" ] || return 0
  _pname="$(basename "$_pdir")"
  if [ -d "$_pdir/skills" ]; then
    for _sk_file in "$_pdir/skills"/*.md; do
      [ -f "$_sk_file" ] || continue
      _sk_name="$(basename "$_sk_file" .md)"
      rnex_unregister_user_skill "$_sk_name" "$_pname"
      rnex_unregister_user_skill "$_sk_name"
    done
  fi
}

clean_provider_ignore() {
  _file="$1"
  [ -f "$_file" ] || return 0
  if grep -q '!repos/\*' "$_file" 2>/dev/null; then
    _non_rnex="$(grep -vE '^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)' "$_file" 2>/dev/null | grep -v '^!repos/\*' | tr -d " \t\r\n")"
    if [ -z "$_non_rnex" ]; then
      rm -f "$_file"
      log_ok "Removed $(basename "$_file")"
    else
      _tmp="$(mktemp)"
      grep -vE '(^[ ]*#.*(Cursor|Gemini|Repo Nexus|member repos)|!repos/\*)' "$_file" > "$_tmp" && mv "$_tmp" "$_file"
      log_ok "Removed !repos/* un-ignore from $(basename "$_file")"
    fi
  fi
}

clean_provider_agents() {
  _ag_dir="$1"
  _ext="${2:-.md}"
  [ -d "$_ag_dir" ] || return 0
  rm -f "$_ag_dir/wiki-curator${_ext}" 2>/dev/null || true

  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$NEXUS_DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
    [ -d "$_pdir" ] || continue
    [ -d "$_pdir/agents" ] || continue
    for _afile in "$_pdir/agents"/*.md; do
      [ -f "$_afile" ] || continue
      _aname="$(basename "$_afile" .agent.md)"
      _aname="$(basename "$_aname" .md)"
      rm -f "$_ag_dir/${_aname}${_ext}" 2>/dev/null || true
    done
  done

  rmdir "$_ag_dir" 2>/dev/null || true
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

  # Purge any plugin-specific skills from .rnex/skills/
  rm -f "$NEXUS_DIR/.rnex/skills/wiki-ingest.md" "$NEXUS_DIR/.rnex/skills/wiki-lint.md" \
        "$NEXUS_DIR/.rnex/skills/rnex-wiki-ingest.md" "$NEXUS_DIR/.rnex/skills/rnex-wiki-lint.md" 2>/dev/null || true

  # Purge stale unprefixed wiki user skills across provider directories
  for _p_dir in $(get_active_provider_skill_dirs 2>/dev/null || true); do
    rm -f "$NEXUS_DIR/$_p_dir/rnex-wiki-ingest.md" "$NEXUS_DIR/$_p_dir/rnex-wiki-lint.md" 2>/dev/null || true
    rm -rf "$NEXUS_DIR/$_p_dir/rnex-wiki-ingest" "$NEXUS_DIR/$_p_dir/rnex-wiki-lint" 2>/dev/null || true
  done

  # Register core User Skills across active provider directories
  for _sk_file in "$NEXUS_DIR/.rnex/skills"/*.md; do
    [ -f "$_sk_file" ] || continue
    _sk_name="$(basename "$_sk_file" .md)"
    rnex_register_user_skill "$_sk_name" ".rnex/skills/${_sk_name}.md"
  done
}

sync_claude() {
  if claude_plugin_enabled; then
    if claude_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    else
      clean_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    fi
    if ! claude_skills_enabled; then
      clean_provider_user_skills "$NEXUS_DIR/.claude/skills"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    clean_provider_user_skills "$NEXUS_DIR/.claude/skills"
  fi
  rm -rf "$NEXUS_DIR/.claude/commands" "$NEXUS_DIR/.claude/prompts" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.claude" 2>/dev/null || true
}

sync_gemini() {
  if gemini_plugin_enabled; then
    _gi="$NEXUS_DIR/.geminiignore"
    if [ ! -f "$_gi" ]; then
      cat > "$_gi" <<GI_EOF
# Gemini CLI file discovery un-ignore for member repos
!repos/*
GI_EOF
      log_ok "Created .geminiignore (enabling Gemini CLI file discovery for member repos)"
    elif ! grep -q '!repos/\*' "$_gi" 2>/dev/null; then
      printf '\n# Gemini CLI file discovery un-ignore for member repos\n!repos/*\n' >> "$_gi"
      log_dim "Added !repos/* to .geminiignore"
    fi

    if gemini_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    else
      clean_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    fi
    if ! gemini_skills_enabled; then
      clean_provider_user_skills "$NEXUS_DIR/.gemini/skills"
    fi
  else
    clean_provider_ignore "$NEXUS_DIR/.geminiignore"
    clean_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    clean_provider_user_skills "$NEXUS_DIR/.gemini/skills"
  fi
  rm -rf "$NEXUS_DIR/.gemini/prompts" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.gemini" 2>/dev/null || true
}

sync_cursor() {
  if cursor_plugin_enabled; then
    _ci="$NEXUS_DIR/.cursorignore"
    if [ ! -f "$_ci" ]; then
      cat > "$_ci" <<CI_EOF
# Cursor codebase indexing un-ignore for member repos
!repos/*
CI_EOF
      log_ok "Created .cursorignore (enabling Cursor indexing for member repos)"
    elif ! grep -q '!repos/\*' "$_ci" 2>/dev/null; then
      printf '\n# Cursor codebase indexing un-ignore for member repos\n!repos/*\n' >> "$_ci"
      log_dim "Added !repos/* to .cursorignore"
    fi

    if cursor_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/.cursorrules"
      mkdir -p "$NEXUS_DIR/.cursor/rules"
      _c_body="$(mktemp)"
      get_rnex_instructions > "$_c_body"
      {
        printf -- '---\ndescription: Repo Nexus Virtual Meta-Repo routing protocol\nglobs: *\nalwaysApply: true\n---\n\n%s\n' "$AI_MARKER_START"
        cat "$_c_body"
        printf '\n%s\n' "$AI_MARKER_END"
      } > "$NEXUS_DIR/.cursor/rules/rnex-context.mdc"
      rm -f "$_c_body"
      rm -f "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
    else
      clean_rnex_instructions "$NEXUS_DIR/.cursorrules"
      rm -f "$NEXUS_DIR/.cursor/rules/rnex-context.mdc" "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
    fi
    if ! cursor_skills_enabled; then
      clean_provider_user_skills "$NEXUS_DIR/.cursor/rules"
    fi
  else
    clean_provider_ignore "$NEXUS_DIR/.cursorignore"
    clean_rnex_instructions "$NEXUS_DIR/.cursorrules"
    rm -f "$NEXUS_DIR/.cursor/rules/rnex-context.mdc" "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
    clean_provider_user_skills "$NEXUS_DIR/.cursor/rules"
  fi
  rm -rf "$NEXUS_DIR/.cursor/prompts" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.cursor/rules" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.cursor" 2>/dev/null || true
}

sync_windsurf() {
  if windsurf_plugin_enabled; then
    if windsurf_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    else
      clean_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    fi
    if ! windsurf_skills_enabled; then
      clean_provider_user_skills "$NEXUS_DIR/.windsurf/rules"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    clean_provider_user_skills "$NEXUS_DIR/.windsurf/rules"
  fi
  rm -rf "$NEXUS_DIR/.windsurf/prompts" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.windsurf/rules" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.windsurf" 2>/dev/null || true
}

sync_copilot() {
  if copilot_plugin_enabled; then
    if copilot_instructions_enabled; then
      mkdir -p "$NEXUS_DIR/.github"
      merge_rnex_instructions "$NEXUS_DIR/.github/copilot-instructions.md"
    else
      clean_rnex_instructions "$NEXUS_DIR/.github/copilot-instructions.md"
    fi
    if ! copilot_skills_enabled; then
      clean_provider_user_skills "$NEXUS_DIR/.github/skills"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/.github/copilot-instructions.md"
    clean_provider_user_skills "$NEXUS_DIR/.github/skills"
  fi
  clean_provider_agents "$NEXUS_DIR/.github/agents" ".agent.md"
  rm -rf "$NEXUS_DIR/.github/prompts" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.github" 2>/dev/null || true
}

sync_ai_providers() {
  sync_copilot
  sync_claude
  sync_gemini
  sync_cursor
  sync_windsurf
}

sync_skills() {
  write_rnex_env_script "$NEXUS_DIR"
  sync_rnex_base_assets
  sync_ai_providers
}

