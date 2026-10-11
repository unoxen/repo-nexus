---
layout: home

hero:
  name: "Repo Nexus"
  text: "Virtual Meta-Repo Companion"
  tagline: "Unite independent repositories into a cohesive AI-enabled workspace without Git submodules or monorepo migrations."
  image:
    src: /logo.svg
    alt: Repo Nexus Logo
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: CLI Reference
      link: /cli/
    - theme: alt
      text: GitHub
      link: https://github.com/unoxen/repo-nexus

features:
  - icon: ⚡
    title: Pure POSIX Shell & Zero Dependencies
    details: Written in pure /bin/sh. Installs instantly via npm/npx or a single curl binary on macOS, Linux, and WSL2.
  - icon: 🗂️
    title: No Git Submodules
    details: Autonomous member repositories clone directly into ./repos/ while remaining independent Git repositories. No detached HEAD hell.
  - icon: 🤖
    title: Scoped AI Context Mirroring
    details: Automatically projects shared routing rules, prompts, and skills into Claude Code, Cursor, Copilot, Gemini, and Windsurf formats.
  - icon: 🧠
    title: Karpathy LLM Wiki Architecture
    details: Built-in support for Andrej Karpathy's 4 cardinal principles for coding agents, context engineering, and autonomous LLM wikis.
  - icon: ⚙️
    title: Two-Level Configuration
    details: Commit team-wide defaults in rnex.yaml while allowing developers to maintain local overrides in .local.rnex.yaml.
  - icon: 🔄
    title: Multi-Repo Batch Execution
    details: Run tests, linters, or git commands across all active repositories in sequence with rnex exec.
---

<div class="quickstart-box" style="margin-top: 2rem;">

## Quick Start in 60 Seconds

::: code-group

```sh [npx (Recommended)]
# Initialize a new workspace with interactive assistant setup
npx repo-nexus init

# Add your repositories
rnex add backend git@github.com:my-org/api.git
rnex add frontend git@github.com:my-org/web.git

# Clone all repositories
rnex clone
```

```sh [npm]
# Install globally
npm install -g repo-nexus

# Initialize and clone
rnex init
rnex clone
```

```sh [curl]
# Download single executable binary directly
curl -fsSL https://raw.githubusercontent.com/unoxen/repo-nexus/main/rnex -o /usr/local/bin/rnex
chmod +x /usr/local/bin/rnex
rnex --version
```

:::

</div>
