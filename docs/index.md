---
layout: doc
title: Repo Nexus (rnex) | Virtual Meta Repository & Nexus Repository (Meta Repo / Nexus Repo)
description: Lightweight, zero-dependency Virtual Meta Repository (meta repo) and Nexus Repository (nexus repo) manager for multi-repo workspaces and shared AI context (no git submodules).
head:
  - - meta
    - name: keywords
      content: nexus repository, meta repository, nexus repo, meta repo, virtual meta repository, virtual meta-repo, multi-repo workspace, repo nexus, rnex
---

# Welcome to Repo Nexus (rnex) — Virtual Meta Repository & Nexus Repository

<div class="rnex-hero-wrapper">
<div class="rnex-hero-content">

<p class="rnex-hero-lead">
The zero-dependency <strong>nexus repository</strong> (<strong>nexus repo</strong>) and <strong>meta repository</strong> (<strong>meta repo</strong>) to unite independent Git repositories into a cohesive AI-enabled workspace—without Git submodules or monorepo migrations.
</p>

<div class="rnex-hero-actions">
<a class="rnex-action-btn primary" href="./introduction/quick-start">Get Started</a>
<a class="rnex-action-btn secondary" href="./introduction/why-rnex">Why rnex?</a>
<a class="rnex-action-btn secondary" href="./reference/cli">CLI Reference</a>
<a class="rnex-action-btn tertiary" href="https://github.com/unoxen/repo-nexus" target="_blank" rel="noreferrer">GitHub</a>
</div>

</div>
<div class="rnex-hero-image">
<img src="/home.png" alt="Repo Nexus Fan" />
</div>
</div>

---

## Key Highlights

<div class="rnex-features-grid">
  <div class="rnex-feature-card">
    <div class="rnex-feature-icon">⚡</div>
    <h3>Pure POSIX Shell & Zero Runtime Dependencies</h3>
    <p>Written entirely in pure, standard <code>/bin/sh</code>. Installs instantly via npm, npx, or a single curl executable on macOS, Linux, and WSL2.</p>
  </div>
  <div class="rnex-feature-card">
    <div class="rnex-feature-icon">🗂️</div>
    <h3>No Git Submodules</h3>
    <p>Autonomous member repositories clone directly into <code>./repos/</code> as independent Git repositories with their own branches, tags, and remotes. No detached HEAD traps.</p>
  </div>
  <div class="rnex-feature-card">
    <div class="rnex-feature-icon">🤖</div>
    <h3>Universal AI Context Mirroring</h3>
    <p>Scoped routing instructions are projected across Claude Code, Cursor, Codex, Gemini, Copilot, and Windsurf without cross-repository context leakage.</p>
  </div>
  <div class="rnex-feature-card">
    <div class="rnex-feature-icon">🧠</div>
    <h3>Karpathy LLM Wiki Architecture</h3>
    <p>Built-in knowledge graph with automated ingest, linting, and a bounded ~500-word hot cache (<code>hot.md</code>) designed for autonomous AI agents.</p>
  </div>
  <div class="rnex-feature-card">
    <div class="rnex-feature-icon">⚙️</div>
    <h3>Two-Level Configuration</h3>
    <p>Commit team-wide standards in <code>rnex.yaml</code> while developers maintain personal machine overrides and private tokens in <code>.local.rnex.yaml</code>.</p>
  </div>
  <div class="rnex-feature-card">
    <div class="rnex-feature-icon">🔄</div>
    <h3>Multi-Repo Batch Execution</h3>
    <p>Run tests, linters, or git commands across all enabled member repositories sequentially with <code>rnex exec</code>, capturing exact exit codes.</p>
  </div>
</div>

---

## Install rnex

Initialize a unified meta repository (meta repo) and nexus repository (nexus repo) workspace and connect member repositories in three simple commands:

::: code-group

```sh [npx (Recommended)]
# Initialize a new workspace with interactive assistant setup
npx repo-nexus init

# Add your repositories
rnex repo add git@github.com:my-org/api.git --name backend
rnex repo add git@github.com:my-org/web.git --name frontend

# Clone all declared repositories
rnex clone
```

```sh [npm (Global)]
# Install globally via npm registry
npm install -g repo-nexus

# Initialize and clone
rnex init
rnex clone
```

```sh [curl (Standalone)]
# Install via zero-dependency standalone installer (no Node.js required)
curl -fsSL https://raw.githubusercontent.com/unoxen/repo-nexus/main/scripts/install.sh | sh
rnex --version
```

:::

---

## Navigation & Sections

* **[Introduction](./introduction/why-rnex)**: Understand why the Virtual Meta-Repo model succeeds where monorepos and Git submodules fall short, follow the quick start tutorial, and inspect practical examples.
* **[Documentation](./documentation/architecture)**: Deep dive into the architecture, configuration schema, workflows, workspace lifecycle, and plugin ecosystem.
* **[Reference](./reference/cli)**: Complete syntax and options for `rnex` CLI commands, lifecycle hooks (`rnex_hooks`), Git hooks (`git.hooks`), and environment variables.
* **[Plugins](./plugins/karpathy-llm)**: Explore first-class plugins for the Karpathy LLM Wiki, Claude Code, OpenAI Codex, Cursor, Gemini, Copilot, and Windsurf.
* **[FAQ](./faq/general)**: Review frequently asked questions, comparisons with Git submodules/monorepos, and troubleshooting tips.
