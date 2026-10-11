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
  cat <<'AGENTS_EOF'
# Multi-Repo AI Workspace Context

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing Protocol for AI Assistants

### Mandatory Session Startup

Before answering the first task or making any task-specific tool call in a new session:

1. **Read Configuration First (Highest Priority)**: Inspect and read `.local.rnex.yaml` (if present) and `rnex.yaml` to identify workspace structure (`repos_dir`), active member repositories (`repos/`), and enabled plugins.
   - `.local.rnex.yaml` takes highest priority over `rnex.yaml`.
   - Repositories are enabled by default unless explicitly marked `enabled: false`. Disabled repositories are excluded from active tasks.
2. Inspect instructions for every enabled Repo Nexus plugin under `.rnex/plugins/<plugin-name>/`.
3. If `wiki/` is present: read `wiki/hot.md` and `wiki/index.md` to orient on architecture and domain concepts.
4. Follow links from the index to wiki pages relevant to the request.
5. Only then inspect member repositories (`repos/<name>/`) or produce an answer.

This is a hard gate, not optional orientation. Complete it once per session and retain the resulting context; do not repeatedly reload these files.

## Prompts & Workflows
For task-specific agent workflows (cross-repo features, workspace audits, wiki maintenance), inspect `.rnex/prompts/index.md`.

## Member Repositories (`repos/<name>/`)
Each member repository is an autonomous Git repository. For repository-specific instructions, inspect `repos/<name>/.rnex/`.

## Git Operations
Commit and push changes directly within the respective member repository root (`repos/<name>/`).
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
  if ! copilot_instructions_enabled; then
    clean_rnex_instructions "$_dst_ci"
    return 0
  fi

  mkdir -p "$NEXUS_DIR/.github"
  _body_tmp="$(mktemp)"

  {
    cat <<'EOF'
# GitHub Copilot Instructions (Repo Nexus Virtual Meta-Repo)

This workspace operates as a **Repo Nexus Virtual Meta-Repo** uniting independent repositories.

## Routing & Operating Protocol
1. Inspect `.local.rnex.yaml` when present, then `rnex.yaml`.
2. Master operational prompts are indexed at `.rnex/prompts/index.md` (and mirrored in `.github/prompts/`).
3. Member repositories reside in `repos/<name>/`. Inspect `repos/<name>/.rnex/` for repository-specific context.
4. Perform Git commits directly inside member repository roots (`repos/<name>/`).
EOF

    # Append active plugins instructions & rules
    _active_p="$(yaml_list_plugins)"
    if [ -n "$_active_p" ]; then
      printf '\n## Active Plugins & Guidelines\n'
      echo "$_active_p" | while read -r _pname; do
        [ -n "$_pname" ] || continue
        yaml_plugin_enabled "$_pname" || continue
        [ "$_pname" != "copilot" ] || continue
        _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
        [ -n "$_pdir" ] || continue
        _pdesc="$(plugin_get_field "$_pdir" "description")"
        printf '\n### Plugin: %s\n' "$_pname"
        [ -n "$_pdesc" ] && printf '%s\n\n' "$_pdesc"

        for _rfile in "$_pdir"/rules/*.md "$NEXUS_DIR/.rnex/plugins/$_pname"/rules/*.md; do
          if [ -f "$_rfile" ]; then
            printf '#### Rules (%s)\n' "$(basename "$_rfile")"
            cat "$_rfile"
            printf '\n'
            break
          fi
        done

        for _ifile in "$_pdir"/instructions/*.md "$NEXUS_DIR/.rnex/plugins/$_pname"/instructions/*.md; do
          if [ -f "$_ifile" ]; then
            printf '#### Instructions (%s)\n' "$(basename "$_ifile")"
            cat "$_ifile"
            printf '\n'
            break
          fi
        done
      done
    fi
  } > "$_body_tmp"

  if [ ! -f "$_dst_ci" ]; then
    {
      printf '%s\n' "$AI_MARKER_START"
      cat "$_body_tmp"
      printf '\n%s\n' "$AI_MARKER_END"
    } > "$_dst_ci"
  elif grep -q "$AI_MARKER_START" "$_dst_ci" 2>/dev/null; then
    _tmp="$(mktemp)"
    awk -v s="$AI_MARKER_START" -v e="$AI_MARKER_END" -v src="$_body_tmp" '
      $0 ~ s {
        print s
        while ((getline line < src) > 0) print line
        close(src)
        print e
        skip=1
        next
      }
      $0 ~ e { skip=0; next }
      !skip { print }
    ' "$_dst_ci" > "$_tmp" && mv "$_tmp" "$_dst_ci"
  else
    _tmp="$(mktemp)"
    cat "$_dst_ci" > "$_tmp"
    {
      printf '\n\n%s\n' "$AI_MARKER_START"
      cat "$_body_tmp"
      printf '\n%s\n' "$AI_MARKER_END"
    } >> "$_tmp"
    mv "$_tmp" "$_dst_ci"
  fi
  rm -f "$_body_tmp"
}

sync_prompts() {
  _src_prompts=""
  if [ -d "$SCRIPT_LOCATION/toolkit/prompts" ]; then
    _src_prompts="$SCRIPT_LOCATION/toolkit/prompts"
  elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit/prompts" ]; then
    _src_prompts="$(dirname "$SCRIPT_LOCATION")/toolkit/prompts"
  elif [ -d "$NEXUS_DIR/toolkit/prompts" ]; then
    _src_prompts="$NEXUS_DIR/toolkit/prompts"
  fi

  [ -n "$_src_prompts" ] || return 0

  _dst_prompts="$NEXUS_DIR/.rnex/prompts"
  mkdir -p "$_dst_prompts"

  for _pfile in "$_src_prompts"/*.md; do
    [ -f "$_pfile" ] || continue
    _b="$(basename "$_pfile")"
    cp -f "$_pfile" "$_dst_prompts/$_b"
  done

  # Purge obsolete setup prompts from workspace prompts
  rm -f "$_dst_prompts/rnex-setup-karpathy-wiki.md" "$_dst_prompts/setup-karpathy-wiki.md" 2>/dev/null || true

  sync_ai_providers
}

sync_provider_prompts() {
  _sp_dir="$1"
  _ext="${2:-.md}"
  [ -n "$_src_prompts" ] || return 0
  mkdir -p "$_sp_dir"

  # Purge obsolete setup prompts
  rm -f "$_sp_dir/rnex-setup-karpathy-wiki${_ext}" "$_sp_dir/setup-karpathy-wiki${_ext}" 2>/dev/null || true

  # Base toolkit prompts
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

  # Active plugins prompts & workflows
  yaml_list_plugins | while read -r _pname; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" || continue
    case "$_pname" in
      copilot|claude|gemini|cursor|windsurf) continue ;;
    esac
    _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || continue

    for _sub in prompts workflows; do
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

sync_provider_skills() {
  _sk_dir="$1"
  mkdir -p "$_sk_dir"

  # Purge obsolete setup skills
  rm -f "$_sk_dir/rnex-setup-karpathy-wiki/SKILL.md" "$_sk_dir/setup-karpathy-wiki/SKILL.md" 2>/dev/null || true
  rmdir "$_sk_dir/rnex-setup-karpathy-wiki" "$_sk_dir/setup-karpathy-wiki" 2>/dev/null || true

  # Base toolkit skills
  for _pfile in "$_src_prompts"/rnex-*.md; do
    [ -f "$_pfile" ] || continue
    _pname="$(basename "$_pfile" .md)"
    _desc="$(awk '
      /^#/ { in_title=1; next }
      in_title && /^[A-Za-z]/ { print; exit }
    ' "$_pfile" 2>/dev/null)"
    [ -n "$_desc" ] || _desc="Repo Nexus prompt for $_pname"

    _dst_sk_dir="$_sk_dir/$_pname"
    mkdir -p "$_dst_sk_dir"
    _dst_sk="$_dst_sk_dir/SKILL.md"
    {
      printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_pname" "$_desc"
      cat "$_pfile"
    } > "$_dst_sk"
  done

  # Active plugins skills, prompts, & workflows
  yaml_list_plugins | while read -r _pname; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" || continue
    case "$_pname" in
      copilot|claude|gemini|cursor|windsurf) continue ;;
    esac
    _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || continue

    # A. Dedicated skills in plugin
    for _s_dir in "$_pdir/skills" "$NEXUS_DIR/.rnex/plugins/$_pname/skills"; do
      [ -d "$_s_dir" ] || continue
      for _s_entry in "$_s_dir"/*; do
        if [ -d "$_s_entry" ] && [ -f "$_s_entry/SKILL.md" ]; then
          _sname="$(basename "$_s_entry")"
          mkdir -p "$_sk_dir/$_sname"
          cp -f "$_s_entry/SKILL.md" "$_sk_dir/$_sname/SKILL.md"
        elif [ -f "$_s_entry" ]; then
          _sname="$(basename "$_s_entry" .md)"
          mkdir -p "$_sk_dir/$_sname"
          if grep -q '^---' "$_s_entry" 2>/dev/null; then
            cp -f "$_s_entry" "$_sk_dir/$_sname/SKILL.md"
          else
            _desc="$(awk '
              /^#/ { in_title=1; next }
              in_title && /^[A-Za-z]/ { print; exit }
            ' "$_s_entry" 2>/dev/null)"
            [ -n "$_desc" ] || _desc="Skill $_sname from plugin $_pname"
            {
              printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_sname" "$_desc"
              cat "$_s_entry"
            } > "$_sk_dir/$_sname/SKILL.md"
          fi
        fi
      done
    done

    # B. Plugin prompts & workflows as skills if not already provided
    for _sub in prompts workflows; do
      for _s_dir in "$_pdir/$_sub" "$NEXUS_DIR/.rnex/plugins/$_pname/$_sub"; do
        [ -d "$_s_dir" ] || continue
        for _pfile in "$_s_dir"/*.md; do
          [ -f "$_pfile" ] || continue
          _base="$(basename "$_pfile" .md)"
          case "$_base" in
            index|README) continue ;;
          esac
          _dst_sk_dir="$_sk_dir/$_base"
          if [ ! -f "$_dst_sk_dir/SKILL.md" ]; then
            mkdir -p "$_dst_sk_dir"
            _desc="$(awk '
              /^#/ { in_title=1; next }
              in_title && /^[A-Za-z]/ { print; exit }
            ' "$_pfile" 2>/dev/null)"
            [ -n "$_desc" ] || _desc="Skill $_base from plugin $_pname"
            {
              printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_base" "$_desc"
              cat "$_pfile"
            } > "$_dst_sk_dir/SKILL.md"
          fi
        done
      done
    done
  done
}

clean_provider_prompts() {
  _sp_dir="$1"
  _ext="${2:-.md}"
  [ -d "$_sp_dir" ] || return 0

  if [ -z "$_src_prompts" ]; then
    if [ -d "$SCRIPT_LOCATION/toolkit/prompts" ]; then
      _src_prompts="$SCRIPT_LOCATION/toolkit/prompts"
    elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit/prompts" ]; then
      _src_prompts="$(dirname "$SCRIPT_LOCATION")/toolkit/prompts"
    elif [ -d "$NEXUS_DIR/toolkit/prompts" ]; then
      _src_prompts="$NEXUS_DIR/toolkit/prompts"
    fi
  fi

  # Remove base toolkit prompts
  rm -f "$_sp_dir/rnex-setup-karpathy-wiki${_ext}" "$_sp_dir/setup-karpathy-wiki${_ext}" 2>/dev/null || true
  if [ -n "$_src_prompts" ]; then
    for _pfile in "$_src_prompts"/rnex-*.md; do
      [ -f "$_pfile" ] || continue
      _pname="$(basename "$_pfile" .md)"
      rm -f "$_sp_dir/${_pname}${_ext}" 2>/dev/null || true
    done
  fi

  # Remove plugin prompts & workflows
  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
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

  if [ -z "$_src_prompts" ]; then
    if [ -d "$SCRIPT_LOCATION/toolkit/prompts" ]; then
      _src_prompts="$SCRIPT_LOCATION/toolkit/prompts"
    elif [ -d "$(dirname "$SCRIPT_LOCATION")/toolkit/prompts" ]; then
      _src_prompts="$(dirname "$SCRIPT_LOCATION")/toolkit/prompts"
    elif [ -d "$NEXUS_DIR/toolkit/prompts" ]; then
      _src_prompts="$NEXUS_DIR/toolkit/prompts"
    fi
  fi

  # Remove base toolkit skills
  rm -f "$_sk_dir/rnex-setup-karpathy-wiki/SKILL.md" "$_sk_dir/setup-karpathy-wiki/SKILL.md" 2>/dev/null || true
  rmdir "$_sk_dir/rnex-setup-karpathy-wiki" "$_sk_dir/setup-karpathy-wiki" 2>/dev/null || true
  if [ -n "$_src_prompts" ]; then
    for _pfile in "$_src_prompts"/rnex-*.md; do
      [ -f "$_pfile" ] || continue
      _pname="$(basename "$_pfile" .md)"
      rm -f "$_sk_dir/$_pname/SKILL.md" 2>/dev/null || true
      rmdir "$_sk_dir/$_pname" 2>/dev/null || true
    done
  fi

  # Remove plugin skills, prompts, workflows, & agents as skills
  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
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

sync_provider_agents() {
  _ag_dir="$1"
  _ext="${2:-.md}"
  mkdir -p "$_ag_dir"

  yaml_list_plugins | while read -r _pname; do
    [ -n "$_pname" ] || continue
    yaml_plugin_enabled "$_pname" || continue
    case "$_pname" in
      copilot|claude|gemini|cursor|windsurf) continue ;;
    esac
    _pdir="$(find_plugin_dir "$_pname" 2>/dev/null || true)"
    [ -n "$_pdir" ] || continue

    for _s_dir in "$_pdir/agents" "$NEXUS_DIR/.rnex/plugins/$_pname/agents"; do
      [ -d "$_s_dir" ] || continue
      for _afile in "$_s_dir"/*.md; do
        [ -f "$_afile" ] || continue
        _aname="$(basename "$_afile" .agent.md)"
        _aname="$(basename "$_aname" .md)"
        _dst_agent="$_ag_dir/${_aname}${_ext}"
        if grep -q '^---' "$_afile" 2>/dev/null; then
          cp -f "$_afile" "$_dst_agent"
        else
          _desc="$(awk '
            /^#/ { in_title=1; next }
            in_title && /^[A-Za-z]/ { print; exit }
          ' "$_afile" 2>/dev/null)"
          [ -n "$_desc" ] || _desc="Agent $_aname from plugin $_pname"
          {
            printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$_aname" "$_desc"
            cat "$_afile"
          } > "$_dst_agent"
        fi
      done
    done
  done
}

clean_provider_agents() {
  _ag_dir="$1"
  _ext="${2:-.md}"
  [ -d "$_ag_dir" ] || return 0

  for _pdir in "$SCRIPT_LOCATION/toolkit/plugins"/* "$DIR/toolkit/plugins"/* "$NEXUS_DIR/.rnex/plugins"/*; do
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

sync_copilot() {
  if copilot_prompts_enabled; then
    sync_provider_prompts "$NEXUS_DIR/.github/prompts" ".prompt.md"
  else
    clean_provider_prompts "$NEXUS_DIR/.github/prompts" ".prompt.md"
  fi

  if copilot_skills_enabled; then
    sync_provider_skills "$NEXUS_DIR/.github/skills"
  else
    clean_provider_skills "$NEXUS_DIR/.github/skills"
  fi

  if copilot_agents_enabled; then
    sync_provider_agents "$NEXUS_DIR/.github/agents" ".agent.md"
    if copilot_skills_enabled; then
      for _ag_file in "$NEXUS_DIR/.github/agents"/*.agent.md; do
        [ -f "$_ag_file" ] || continue
        _aname="$(basename "$_ag_file" .agent.md)"
        mkdir -p "$NEXUS_DIR/.github/skills/$_aname"
        cp -f "$_ag_file" "$NEXUS_DIR/.github/skills/$_aname/SKILL.md"
      done
    fi
  else
    clean_provider_agents "$NEXUS_DIR/.github/agents" ".agent.md"
  fi

  sync_copilot_instructions
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

    if claude_skills_enabled; then
      sync_provider_skills "$NEXUS_DIR/.claude/skills"
    else
      clean_provider_skills "$NEXUS_DIR/.claude/skills"
    fi

    if claude_agents_enabled; then
      sync_provider_agents "$NEXUS_DIR/.claude/agents" ".md"
    else
      clean_provider_agents "$NEXUS_DIR/.claude/agents" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/CLAUDE.md"
    clean_provider_prompts "$NEXUS_DIR/.claude/commands" ".md"
    clean_provider_prompts "$NEXUS_DIR/.claude/prompts" ".md"
    clean_provider_skills "$NEXUS_DIR/.claude/skills"
    clean_provider_agents "$NEXUS_DIR/.claude/agents" ".md"
    rmdir "$NEXUS_DIR/.claude" 2>/dev/null || true
  fi
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

    if gemini_skills_enabled; then
      sync_provider_skills "$NEXUS_DIR/.gemini/skills"
    else
      clean_provider_skills "$NEXUS_DIR/.gemini/skills"
    fi

    if gemini_agents_enabled; then
      sync_provider_agents "$NEXUS_DIR/.gemini/agents" ".md"
    else
      clean_provider_agents "$NEXUS_DIR/.gemini/agents" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/GEMINI.md"
    clean_provider_prompts "$NEXUS_DIR/.gemini/prompts" ".prompt.md"
    clean_provider_skills "$NEXUS_DIR/.gemini/skills"
    clean_provider_agents "$NEXUS_DIR/.gemini/agents" ".md"
    rmdir "$NEXUS_DIR/.gemini/rules" 2>/dev/null || true
    rmdir "$NEXUS_DIR/.gemini" 2>/dev/null || true
  fi
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
      } > "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc"
      rm -f "$_c_body"
    else
      clean_rnex_instructions "$NEXUS_DIR/.cursorrules"
      rm -f "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
      rmdir "$NEXUS_DIR/.cursor/rules" 2>/dev/null || true
    fi

    if cursor_prompts_enabled; then
      sync_provider_prompts "$NEXUS_DIR/.cursor/prompts" ".md"
    else
      clean_provider_prompts "$NEXUS_DIR/.cursor/prompts" ".md"
    fi

    if cursor_skills_enabled; then
      sync_provider_skills "$NEXUS_DIR/.cursor/skills"
    else
      clean_provider_skills "$NEXUS_DIR/.cursor/skills"
    fi

    if cursor_agents_enabled; then
      sync_provider_agents "$NEXUS_DIR/.cursor/agents" ".md"
    else
      clean_provider_agents "$NEXUS_DIR/.cursor/agents" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/.cursorrules"
    rm -f "$NEXUS_DIR/.cursor/rules/repo-nexus.mdc" 2>/dev/null || true
    rmdir "$NEXUS_DIR/.cursor/rules" 2>/dev/null || true
    clean_provider_prompts "$NEXUS_DIR/.cursor/prompts" ".md"
    clean_provider_skills "$NEXUS_DIR/.cursor/skills"
    clean_provider_agents "$NEXUS_DIR/.cursor/agents" ".md"
    rmdir "$NEXUS_DIR/.cursor" 2>/dev/null || true
  fi
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

    if windsurf_skills_enabled; then
      sync_provider_skills "$NEXUS_DIR/.windsurf/skills"
    else
      clean_provider_skills "$NEXUS_DIR/.windsurf/skills"
    fi

    if windsurf_agents_enabled; then
      sync_provider_agents "$NEXUS_DIR/.windsurf/agents" ".md"
    else
      clean_provider_agents "$NEXUS_DIR/.windsurf/agents" ".md"
    fi
  else
    clean_rnex_instructions "$NEXUS_DIR/.windsurfrules"
    clean_provider_prompts "$NEXUS_DIR/.windsurf/prompts" ".md"
    clean_provider_skills "$NEXUS_DIR/.windsurf/skills"
    clean_provider_agents "$NEXUS_DIR/.windsurf/agents" ".md"
    rmdir "$NEXUS_DIR/.windsurf" 2>/dev/null || true
  fi
}

sync_ai_providers() {
  sync_copilot
  sync_claude
  sync_gemini
  sync_cursor
  sync_windsurf
}
