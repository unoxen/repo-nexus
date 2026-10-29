import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

const base = (process.env.BASE_URL as `/${string}/`) || '/repo-nexus/'

export default withMermaid(
  defineConfig({
    title: 'Repo Nexus (rnex)',
    titleTemplate: ':title | rnex',
    description: 'Lightweight Virtual Meta Repository (meta repo) and Nexus Repository (nexus repo) manager for multi-repo workspaces and shared AI context',

    // Dynamic base URL: defaults to '/repo-nexus/' for GitHub Pages, '/' for root/custom domain
    base,

    cleanUrls: true,
    lastUpdated: true,

    sitemap: {
      hostname: 'https://unoxen.github.io/repo-nexus/'
    },

    head: [
      ['link', { rel: 'canonical', href: 'https://unoxen.github.io/repo-nexus/' }],
      ['meta', { property: 'og:type', content: 'website' }],
      ['meta', { property: 'og:title', content: 'Repo Nexus (rnex) - Virtual Meta Repository & Nexus Repository (Meta Repo / Nexus Repo)' }],
      ['meta', { property: 'og:description', content: 'Lightweight Virtual Meta Repository (meta repo) and Nexus Repository (nexus repo) manager with auto-synced AI context (no git submodules)' }],
      ['meta', { property: 'og:url', content: 'https://unoxen.github.io/repo-nexus/' }],
      ['meta', { name: 'keywords', content: 'nexus repository, meta repository, nexus repo, meta repo, virtual meta repository, virtual meta-repo, multi-repo workspace, repo nexus, rnex' }],
      [
        'script',
        { type: 'application/ld+json' },
        JSON.stringify({
          '@context': 'https://schema.org',
          '@type': 'SoftwareApplication',
          'name': 'Repo Nexus',
          'alternateName': 'rnex',
          'applicationCategory': 'DeveloperApplication',
          'operatingSystem': 'POSIX (macOS, Linux, WSL)',
          'description': 'Lightweight Virtual Meta Repository (meta repo) and Nexus Repository (nexus repo) manager for multi-repo workspaces and shared AI context',
          'url': 'https://unoxen.github.io/repo-nexus/',
          'codeRepository': 'https://github.com/unoxen/repo-nexus',
          'keywords': 'nexus repository, meta repository, nexus repo, meta repo, virtual meta repository, multi-repo'
        })
      ],
      ['meta', { name: 'theme-color', content: '#10b981' }],
      ['meta', { name: 'og:site_name', content: 'Repo Nexus (rnex)' }],
      ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
      ['meta', { name: 'twitter:title', content: 'Repo Nexus (rnex) - Virtual Meta Repository & Nexus Repository (Meta Repo / Nexus Repo)' }],
      ['meta', { name: 'twitter:description', content: 'Lightweight Virtual Meta Repository (meta repo) and Nexus Repository (nexus repo) manager with auto-synced AI context (no git submodules)' }],
      ['link', { rel: 'icon', type: 'image/png', href: `${base}logo.png` }]
    ],

    markdown: {
      lineNumbers: true
    },

    themeConfig: {
      siteTitle: 'Repo Nexus (rnex)',
      logo: {
        src: '/logo.png',
        alt: 'Repo Nexus Logo'
      },

      lastUpdated: {
        text: 'Last updated',
        formatOptions: {
          dateStyle: 'short'
        }
      },

      nav: [
        {
          text: 'Introduction',
          activeMatch: '^/(introduction/|$)',
          items: [
            { text: 'Welcome', link: '/' },
            { text: 'Why rnex?', link: '/introduction/why-rnex' },
            { text: 'Quick Start', link: '/introduction/quick-start' },
            {
              text: 'Examples',
              items: [
                { text: 'Multi-Repo Microservices', link: '/introduction/examples/microservices' },
                { text: 'Full-Stack AI Context', link: '/introduction/examples/fullstack-ai' },
                { text: 'Karpathy LLM Wiki', link: '/introduction/examples/llm-wiki' },
                { text: 'Selective Checkout', link: '/introduction/examples/selective-checkout' }
              ]
            }
          ]
        },
        {
          text: 'Documentation',
          activeMatch: '^/documentation/',
          items: [
            { text: 'Architecture', link: '/documentation/architecture' },
            { text: 'Configuration', link: '/documentation/configuration' },
            { text: 'Workflows & Automation', link: '/documentation/workflows' },
            { text: 'Workspace Lifecycle', link: '/documentation/workspace-lifecycle' },
            { text: 'Plugin Ecosystem', link: '/documentation/plugin-ecosystem' }
          ]
        },
        {
          text: 'Reference',
          activeMatch: '^/reference/',
          items: [
            { text: 'CLI Reference', link: '/reference/cli' },
            { text: 'Lifecycle Hooks', link: '/reference/rnex-hooks' },
            { text: 'Git Hooks', link: '/reference/git-hooks' },
            { text: 'Environment & Layout', link: '/reference/environment' }
          ]
        },
        {
          text: 'Plugins',
          activeMatch: '^/plugins/',
          items: [
            { text: 'Karpathy LLM Wiki', link: '/plugins/karpathy-llm' },
            { text: 'Claude Code', link: '/plugins/claude' },
            { text: 'OpenAI Codex', link: '/plugins/codex' },
            { text: 'Cursor', link: '/plugins/cursor' },
            { text: 'Google Gemini & Antigravity', link: '/plugins/gemini' },
            { text: 'GitHub Copilot', link: '/plugins/copilot' },
            { text: 'Windsurf', link: '/plugins/windsurf' }
          ]
        },
        {
          text: 'FAQ',
          activeMatch: '^/faq/',
          items: [
            { text: 'General & Architectural FAQ', link: '/faq/general' },
            { text: 'Troubleshooting', link: '/faq/troubleshooting' }
          ]
        }
      ],

      sidebar: [
        {
          text: 'Introduction',
          collapsed: false,
          items: [
            { text: 'Welcome', link: '/' },
            { text: 'Why rnex?', link: '/introduction/why-rnex' },
            { text: 'Quick Start', link: '/introduction/quick-start' },
            {
              text: 'Examples',
              collapsed: false,
              items: [
                { text: 'Multi-Repo Microservices', link: '/introduction/examples/microservices' },
                { text: 'Full-Stack AI Context', link: '/introduction/examples/fullstack-ai' },
                { text: 'Karpathy LLM Wiki', link: '/introduction/examples/llm-wiki' },
                { text: 'Selective Checkout', link: '/introduction/examples/selective-checkout' }
              ]
            }
          ]
        },
        {
          text: 'Documentation',
          collapsed: false,
          items: [
            { text: 'Architecture', link: '/documentation/architecture' },
            { text: 'Configuration', link: '/documentation/configuration' },
            { text: 'Workflows & Automation', link: '/documentation/workflows' },
            { text: 'Workspace Lifecycle', link: '/documentation/workspace-lifecycle' },
            { text: 'Plugin Ecosystem', link: '/documentation/plugin-ecosystem' }
          ]
        },
        {
          text: 'Reference',
          collapsed: false,
          items: [
            { text: 'CLI Reference', link: '/reference/cli' },
            { text: 'Lifecycle Hooks', link: '/reference/rnex-hooks' },
            { text: 'Git Hooks', link: '/reference/git-hooks' },
            { text: 'Environment & Layout', link: '/reference/environment' }
          ]
        },
        {
          text: 'Plugins',
          collapsed: false,
          items: [
            { text: 'Karpathy LLM Wiki', link: '/plugins/karpathy-llm' },
            { text: 'Claude Code (CLAUDE.md)', link: '/plugins/claude' },
            { text: 'OpenAI Codex (CODEX.md)', link: '/plugins/codex' },
            { text: 'Cursor (.cursorrules)', link: '/plugins/cursor' },
            { text: 'Google Gemini (GEMINI.md)', link: '/plugins/gemini' },
            { text: 'GitHub Copilot (.github)', link: '/plugins/copilot' },
            { text: 'Windsurf (.windsurfrules)', link: '/plugins/windsurf' }
          ]
        },
        {
          text: 'FAQ',
          collapsed: false,
          items: [
            { text: 'General & Architectural FAQ', link: '/faq/general' },
            { text: 'Troubleshooting', link: '/faq/troubleshooting' }
          ]
        }
      ],

      outline: {
        level: [2, 3],
        label: 'On this page'
      },

      search: {
        provider: 'local',
        options: {
          detailedView: true
        }
      },

      socialLinks: [
        { icon: 'github', link: 'https://github.com/unoxen/repo-nexus' },
        { icon: 'npm', link: 'https://www.npmjs.com/package/repo-nexus' }
      ],

      footer: {
        copyright: 'Copyright © 2026 Repo Nexus · Apache 2.0 License'
      }
    }
  })
)
