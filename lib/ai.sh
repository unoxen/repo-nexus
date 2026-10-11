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
}

# ---- AI Instructions Management (Routing-Only) ----------------------------

AI_MARKER_START="<!-- REPO-NEXUS:START -->"
AI_MARKER_END="<!-- REPO-NEXUS:END -->"

get_rnex_instructions() {
  _wiki_dir="$(karpathy_wiki_dir)"
  cat <<AGENTS_EOF
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

### Mandatory Session Startup

Before answering the first task or making any task-specific tool call in a new session:

1. **Read Configuration First (Highest Priority)**: Inspect and read \`.local.rnex.yaml\` (if present) and \`rnex.yaml\` to identify workspace structure (\`repos_dir\`), active member repositories (\`repos/\`), and enabled plugins.
   - \`.local.rnex.yaml\` takes highest priority over \`rnex.yaml\`.
   - Repositories are enabled by default unless explicitly marked \`enabled: false\`. Disabled repositories are excluded from active tasks.
2. Inspect instructions for every enabled Repo Nexus plugin under \`.rnex/plugins/<plugin-name>/\`.
3. If \`${_wiki_dir}/\` is present: read \`${_wiki_dir}/hot.md\` and \`${_wiki_dir}/index.md\` to orient on architecture and domain concepts.
4. Follow links from the index to wiki pages relevant to the request.
5. Only then inspect member repositories (\`repos/<name>/\`) or produce an answer.

This is a hard gate, not optional orientation. Complete it once per session and retain the resulting context; do not repeatedly reload these files.

## Workspace Skills, Workflows & Rules
Tools and agents operate on skills, workflows, instructions, and rules located under \`.rnex/\`:
- **Skills**: Inspect \`.rnex/skills/\` and active plugin skills under \`.rnex/plugins/<plugin-name>/skills/\`.
- **Workflows**: Inspect \`.rnex/workflows/\` and active plugin workflows under \`.rnex/plugins/<plugin-name>/workflows/\`.
- **Rules & Instructions**: Inspect \`.rnex/rules/\`, \`.rnex/instructions/\`, and active plugin rules/instructions under \`.rnex/plugins/<plugin-name>/\`.

## Subagents
Autonomous subagents are defined under \`.rnex/agents/\` and active plugin agents under \`.rnex/plugins/<plugin-name>/agents/\` (e.g. \`rnex-wiki-curator.agent.md\`).
- Subagents are kept in \`.rnex/\` and are not mirrored to external provider folders.
- To execute a task requiring a subagent, adopt the role, operational persona, and constraints specified in the corresponding subagent definition file.

## Member Repositories (\`repos/<name>/\`)
Each member repository is an autonomous Git repository. For repository-specific instructions, inspect \`repos/<name>/.rnex/\`.

## Workspace Maintenance
When workspace configuration, routing blocks, plugin assets, or member repository structures require reconciliation or schema upgrades:
- Run \`rnex fix\` (or its alias \`rnex update\` / \`rnex upgrade\`, which runs the unified fix reconciliation with upfront version checking).
- Use \`rnex fix -y\` to non-destructively apply configuration version upgrades automatically.

## Git Operations
Commit and push changes directly within the respective member repository root (\`repos/<name>/\`).
AGENTS_EOF
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
      printf '\n%s\n' "$AI_MARKER_END"
    } > "$_dst"
    rm -f "$_body_tmp"
    log_ok "Created $(basename "$_dst") with Repo Nexus routing instructions"
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

sync_copilot_instructions() {
  _dst_ci="$NEXUS_DIR/.github/copilot-instructions.md"
  clean_rnex_instructions "$_dst_ci"
  rmdir "$NEXUS_DIR/.github" 2>/dev/null || true
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

  # Purge obsolete .rnex/prompts/ directory (prompts are only for IDE provider integration, never inside .rnex/)
  rm -rf "$NEXUS_DIR/.rnex/prompts" 2>/dev/null || true

  # Sync base workflows to .rnex/workflows/
  if [ -n "$_src_toolkit" ] && [ -d "$_src_toolkit/workflows" ]; then
    mkdir -p "$NEXUS_DIR/.rnex/workflows"
    cp -f "$_src_toolkit"/workflows/*.md "$NEXUS_DIR/.rnex/workflows/" 2>/dev/null || true
  fi

  # Sync base skills to .rnex/skills/
  if [ -n "$_src_toolkit" ] && [ -d "$_src_toolkit/skills" ]; then
    mkdir -p "$NEXUS_DIR/.rnex/skills"
    for _sk_dir in "$_src_toolkit"/skills/*; do
      [ -d "$_sk_dir" ] || continue
      _sk_name="$(basename "$_sk_dir")"
      mkdir -p "$NEXUS_DIR/.rnex/skills/$_sk_name"
      cp -f "$_sk_dir"/* "$NEXUS_DIR/.rnex/skills/$_sk_name/" 2>/dev/null || true
    done
  fi
}

sync_prompts() {
  sync_rnex_base_assets
  sync_ai_providers
}

sync_provider_prompts() {
  _sp_dir="$1"
  _ext="${2:-.md}"

  _src_prompts=""
  if [ -d "$SCRIPT_LOCATION/toolkit/prompts" ]; then
    _src_prompts="$SCRIPT_LOCATION/toolkit/prompts"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit/prompts" ]; then
    _src_prompts="$(dirname "$SCRIPT_LOCATION")/toolkit/prompts"
  elif [ -d "$NEXUS_DIR/toolkit/prompts" ]; then
    _src_prompts="$NEXUS_DIR/toolkit/prompts"
  fi

  _src_workflows=""
  if [ -d "$SCRIPT_LOCATION/toolkit/workflows" ]; then
    _src_workflows="$SCRIPT_LOCATION/toolkit/workflows"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit/workflows" ]; then
    _src_workflows="$(dirname "$SCRIPT_LOCATION")/toolkit/workflows"
  elif [ -d "$NEXUS_DIR/toolkit/workflows" ]; then
    _src_workflows="$NEXUS_DIR/toolkit/workflows"
  fi

  [ -n "$_src_prompts" ] || [ -n "$_src_workflows" ] || return 0
  mkdir -p "$_sp_dir"

  # Purge obsolete setup prompts
  rm -f "$_sp_dir/rnex-setup-karpathy-wiki${_ext}" "$_sp_dir/setup-karpathy-wiki${_ext}" 2>/dev/null || true
  rm -f "$_sp_dir/wiki-ingest${_ext}" "$_sp_dir/wiki-lint${_ext}" 2>/dev/null || true

  # Base toolkit prompts (from prompts or workflows)
  if [ -n "$_src_prompts" ]; then
    for _pfile in "$_src_prompts"/rnex-*.md; do
      [ -f "$_pfile" ] || continue
      _pname="$(basename "$_pfile" .md)"
      _desc="$(awk '
        /^#/ { in_title=1; next }
        in_title && /^[A-Za-z]/ { print; exit }
      ' "$_pfile" 2>/dev/null)"
      [ -n "$_desc" ] || _desc="Repo Nexus prompt for $_pname"

      _dst_file="$_sp_dir/${_pname}${_ext}"
      {
        printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_pname" "$_desc"
        cat "$_pfile"
      } > "$_dst_file"
    done
  elif [ -n "$_src_workflows" ]; then
    for _pfile in "$_src_workflows"/rnex-*.md; do
      [ -f "$_pfile" ] || continue
      _pname="$(basename "$_pfile" .md)"
      _desc="$(awk '
        /^#/ { in_title=1; next }
        in_title && /^[A-Za-z]/ { print; exit }
      ' "$_pfile" 2>/dev/null)"
      [ -n "$_desc" ] || _desc="Repo Nexus prompt for $_pname"

      _dst_file="$_sp_dir/${_pname}${_ext}"
      {
        printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_pname" "$_desc"
        cat "$_pfile"
      } > "$_dst_file"
    done
  fi

  # Active plugins prompts & workflows
  yaml_list_plugins | while read -r _pname; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" || continue
    case "$_pname" in
      copilot|claude|gemini|cursor|windsurf) continue ;;
    esac
    _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || continue

    for _sub in workflows prompts; do
      for _s_dir in "$_pdir/$_sub" "$NEXUS_DIR/.rnex/plugins/$_pname/$_sub"; do
        [ -d "$_s_dir" ] || continue
        for _pfile in "$_s_dir"/*.md; do
          [ -f "$_pfile" ] || continue
          _base="$(basename "$_pfile" .md)"
          case "$_base" in
            index|README) continue ;;
          esac
          _desc="$(awk '
            /^#/ { in_title=1; next }
            in_title && /^[A-Za-z]/ { print; exit }
          ' "$_pfile" 2>/dev/null)"
          [ -n "$_desc" ] || _desc="Prompt $_base from plugin $_pname"

          _dst_file="$_sp_dir/${_base}${_ext}"
          {
            printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_base" "$_desc"
            cat "$_pfile"
          } > "$_dst_file"
        done
      done
    done
  done
}

clean_provider_prompts() {
  _sp_dir="$1"
  _ext="${2:-.md}"
  [ -d "$_sp_dir" ] || return 0

  _src_prompts=""
  if [ -d "$SCRIPT_LOCATION/toolkit/prompts" ]; then
    _src_prompts="$SCRIPT_LOCATION/toolkit/prompts"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit/prompts" ]; then
    _src_prompts="$(dirname "$SCRIPT_LOCATION")/toolkit/prompts"
  elif [ -d "$NEXUS_DIR/toolkit/prompts" ]; then
    _src_prompts="$NEXUS_DIR/toolkit/prompts"
  fi

  # Remove base toolkit prompts
  rm -f "$_sp_dir/rnex-setup-karpathy-wiki${_ext}" "$_sp_dir/setup-karpathy-wiki${_ext}" 2>/dev/null || true
  rm -f "$_sp_dir/wiki-ingest${_ext}" "$_sp_dir/wiki-lint${_ext}" 2>/dev/null || true
  if [ -n "$_src_prompts" ]; then
    for _pfile in "$_src_prompts"/rnex-*.md; do
      [ -f "$_pfile" ] || continue
      _pname="$(basename "$_pfile" .md)"
      rm -f "$_sp_dir/${_pname}${_ext}" 2>/dev/null || true
    done
  fi

  for _wfile in "$SCRIPT_LOCATION/toolkit/workflows"/rnex-*.md "$NEXUS_DIR/toolkit/workflows"/rnex-*.md; do
    [ -f "$_wfile" ] || continue
    _wname="$(basename "$_wfile" .md)"
    rm -f "$_sp_dir/${_wname}${_ext}" 2>/dev/null || true
  done

  # Remove plugin prompts & workflows
  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$NEXUS_DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
    [ -d "$_pdir" ] || continue
    for _sub in prompts workflows; do
      [ -d "$_pdir/$_sub" ] || continue
      for _pfile in "$_pdir/$_sub"/*.md; do
        [ -f "$_pfile" ] || continue
        _base="$(basename "$_pfile" .md)"
        case "$_base" in
          index|README) continue ;;
        esac
        rm -f "$_sp_dir/${_base}${_ext}" 2>/dev/null || true
      done
    done
  done

  rmdir "$_sp_dir" 2>/dev/null || true
}

clean_provider_skills() {
  _sk_dir="$1"
  [ -d "$_sk_dir" ] || return 0

  # Remove base toolkit skills
  rm -f "$_sk_dir/rnex-setup-karpathy-wiki/SKILL.md" "$_sk_dir/setup-karpathy-wiki/SKILL.md" 2>/dev/null || true
  rmdir "$_sk_dir/rnex-setup-karpathy-wiki" "$_sk_dir/setup-karpathy-wiki" 2>/dev/null || true
  rm -rf "$_sk_dir/wiki-ingest" "$_sk_dir/wiki-lint" "$_sk_dir/wiki-curator" 2>/dev/null || true

  for _pfile in "$SCRIPT_LOCATION/toolkit/prompts"/rnex-*.md "$NEXUS_DIR/toolkit/prompts"/rnex-*.md \
                "$SCRIPT_LOCATION/toolkit/workflows"/rnex-*.md "$NEXUS_DIR/toolkit/workflows"/rnex-*.md \
                "$SCRIPT_LOCATION/toolkit/skills"/* "$NEXUS_DIR/toolkit/skills"/*; do
    [ -e "$_pfile" ] || continue
    _pname="$(basename "$_pfile" .md)"
    rm -f "$_sk_dir/$_pname/SKILL.md" 2>/dev/null || true
    rmdir "$_sk_dir/$_pname" 2>/dev/null || true
  done

  # Remove plugin skills, prompts, workflows, & agents as skills
  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$NEXUS_DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
    [ -d "$_pdir" ] || continue
    for _sub in skills prompts workflows agents; do
      [ -d "$_pdir/$_sub" ] || continue
      for _s_entry in "$_pdir/$_sub"/*; do
        [ -e "$_s_entry" ] || continue
        _sname="$(basename "$_s_entry" .md)"
        _sname="$(basename "$_sname" .agent.md)"
        case "$_sname" in
          index|README) continue ;;
        esac
        rm -f "$_sk_dir/$_sname/SKILL.md" 2>/dev/null || true
        rmdir "$_sk_dir/$_sname" 2>/dev/null || true
      done
    done
  done

  rmdir "$_sk_dir" 2>/dev/null || true
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
      if [ "$_ag_dir" = "$NEXUS_DIR/.github/agents" ]; then
        rm -f "$NEXUS_DIR/.github/skills/$_aname/SKILL.md" 2>/dev/null || true
        rmdir "$NEXUS_DIR/.github/skills/$_aname" 2>/dev/null || true
      fi
    done
  done

  rmdir "$_ag_dir" 2>/dev/null || true
}

clean_copilot_user_agent_skills() {
  [ -d "$NEXUS_DIR/.github/skills" ] || return 0
  [ -d "$NEXUS_DIR/.github/agents" ] || return 0

  _plugin_agents=" "
  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$NEXUS_DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
    [ -d "$_pdir/agents" ] || continue
    for _afile in "$_pdir/agents"/*.md; do
      [ -f "$_afile" ] || continue
      _aname="$(basename "$_afile" .agent.md)"
      _aname="$(basename "$_aname" .md)"
      _plugin_agents="${_plugin_agents}${_aname} "
    done
  done

  for _ag_file in "$NEXUS_DIR/.github/agents"/*.agent.md; do
    [ -f "$_ag_file" ] || continue
    _aname="$(basename "$_ag_file" .agent.md)"
    case "$_plugin_agents" in
      *" ${_aname} "*) ;;
      *)
        _sk_file="$NEXUS_DIR/.github/skills/$_aname/SKILL.md"
        if [ -f "$_sk_file" ] && cmp -s "$_ag_file" "$_sk_file"; then
          _extra_files="$(find "$NEXUS_DIR/.github/skills/$_aname" -maxdepth 1 -type f ! -name "SKILL.md" 2>/dev/null || true)"
          _extra_dirs="$(find "$NEXUS_DIR/.github/skills/$_aname" -mindepth 1 -type d 2>/dev/null || true)"
          if [ -z "$_extra_files" ] && [ -z "$_extra_dirs" ]; then
            rm -f "$_sk_file" 2>/dev/null || true
            rmdir "$NEXUS_DIR/.github/skills/$_aname" 2>/dev/null || true
          fi
        fi
        ;;
    esac
  done
}

clean_copilot_plugin_agents_as_skills() {
  [ -d "$NEXUS_DIR/.github/skills" ] || return 0
  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$NEXUS_DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
    [ -d "$_pdir" ] || continue
    [ -d "$_pdir/agents" ] || continue
    for _afile in "$_pdir/agents"/*.md; do
      [ -f "$_afile" ] || continue
      _aname="$(basename "$_afile" .agent.md)"
      _aname="$(basename "$_aname" .md)"
      rm -f "$NEXUS_DIR/.github/skills/$_aname/SKILL.md" 2>/dev/null || true
      rmdir "$NEXUS_DIR/.github/skills/$_aname" 2>/dev/null || true
    done
  done
  rm -f "$NEXUS_DIR/.github/skills/wiki-curator/SKILL.md" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.github/skills/wiki-curator" 2>/dev/null || true
}

sync_copilot() {
  if copilot_plugin_enabled && copilot_prompts_enabled; then
    sync_provider_prompts "$NEXUS_DIR/.github/prompts" ".prompt.md"
  else
    clean_provider_prompts "$NEXUS_DIR/.github/prompts" ".prompt.md"
  fi

  clean_provider_skills "$NEXUS_DIR/.github/skills"
  clean_copilot_user_agent_skills
  clean_copilot_plugin_agents_as_skills
  clean_provider_agents "$NEXUS_DIR/.github/agents" ".agent.md"
  sync_copilot_instructions
  rmdir "$NEXUS_DIR/.github" 2>/dev/null || true
}

sync_claude() {
  if claude_plugin_enabled; then
    if claude_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    else
      clean_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    fi

    if claude_prompts_enabled; then
      sync_provider_prompts "$NEXUS_DIR/.claude/commands" ".md"
      sync_provider_prompts "$NEXUS_DIR/.claude/prompts" ".md"
    else
      clean_provider_prompts "$NEXUS_DIR/.claude/commands" ".md"
      clean_provider_prompts "$NEXUS_DIR/.claude/prompts" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    clean_provider_prompts "$NEXUS_DIR/.claude/commands" ".md"
    clean_provider_prompts "$NEXUS_DIR/.claude/prompts" ".md"
  fi

  clean_provider_skills "$NEXUS_DIR/.claude/skills"
  clean_provider_agents "$NEXUS_DIR/.claude/agents" ".md"
  rmdir "$NEXUS_DIR/.claude" 2>/dev/null || true
}

sync_gemini() {
  if gemini_plugin_enabled; then
    if gemini_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    else
      clean_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    fi

    if gemini_prompts_enabled; then
      sync_provider_prompts "$NEXUS_DIR/.gemini/prompts" ".prompt.md"
    else
      clean_provider_prompts "$NEXUS_DIR/.gemini/prompts" ".prompt.md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    clean_provider_prompts "$NEXUS_DIR/.gemini/prompts" ".prompt.md"
  fi

  clean_provider_skills "$NEXUS_DIR/.gemini/skills"
  clean_provider_agents "$NEXUS_DIR/.gemini/agents" ".md"
  rmdir "$NEXUS_DIR/.gemini/rules" 2>/dev/null || true
  rmdir "$NEXUS_DIR/.gemini" 2>/dev/null || true
}

sync_cursor() {
  if cursor_plugin_enabled; then
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
      rmdir "$NEXUS_DIR/.cursor/rules" 2>/dev/null || true
    fi

    if cursor_prompts_enabled; then
      sync_provider_prompts "$NEXUS_DIR/.cursor/prompts" ".md"
    else
      clean_provider_prompts "$NEXUS_DIR/.cursor/prompts" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/.cursorrules"
    rm -f "$NEXUS_DIR/.cursor/rules/rnex-context.mdc" "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
    rmdir "$NEXUS_DIR/.cursor/rules" 2>/dev/null || true
    clean_provider_prompts "$NEXUS_DIR/.cursor/prompts" ".md"
  fi

  clean_provider_skills "$NEXUS_DIR/.cursor/skills"
  clean_provider_agents "$NEXUS_DIR/.cursor/agents" ".md"
  rmdir "$NEXUS_DIR/.cursor" 2>/dev/null || true
}

sync_windsurf() {
  if windsurf_plugin_enabled; then
    if windsurf_instructions_enabled; then
      merge_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    else
      clean_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    fi

    if windsurf_prompts_enabled; then
      sync_provider_prompts "$NEXUS_DIR/.windsurf/prompts" ".md"
    else
      clean_provider_prompts "$NEXUS_DIR/.windsurf/prompts" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    clean_provider_prompts "$NEXUS_DIR/.windsurf/prompts" ".md"
  fi

  clean_provider_skills "$NEXUS_DIR/.windsurf/skills"
  clean_provider_agents "$NEXUS_DIR/.windsurf/agents" ".md"
  rmdir "$NEXUS_DIR/.windsurf" 2>/dev/null || true
}

sync_ai_providers() {
  sync_copilot
  sync_claude
  sync_gemini
  sync_cursor
  sync_windsurf
}
