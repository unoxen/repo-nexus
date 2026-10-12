import { defineConfig } from 'vitepress'

const base = (process.env.BASE_URL as `/${string}/`) || '/repo-nexus/'

export default defineConfig({
  title: 'Repo Nexus (rnex)',
  titleTemplate: ':title | rnex',
  description: 'Zero-Dependency Virtual Meta-Repo Companion for Multi-Repo Workspaces & Scoped AI Context',

  // Dynamic base URL: defaults to '/repo-nexus/' for GitHub Pages, '/' for root/custom domain
  base,

  cleanUrls: true,
  lastUpdated: true,

  srcExclude: [
    'AGENTS.sample.md'
  ],

  sitemap: {
    hostname: `https://unoxen.github.io${base}`
  },

  head: [
    ['meta', { name: 'theme-color', content: '#10b981' }],
    ['meta', { name: 'og:type', content: 'website' }],
    ['meta', { name: 'og:site_name', content: 'Repo Nexus (rnex)' }],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    ['link', { rel: 'icon', type: 'image/jpeg', href: `${base}logo.jpg` }]
  ],

  markdown: {
    lineNumbers: true
  },

  themeConfig: {
    siteTitle: 'Repo Nexus (rnex)',
    logo: '/logo.jpg',

    editLink: {
      pattern: 'https://github.com/unoxen/repo-nexus/edit/main/docs/:path',
      text: 'Edit this page on GitHub'
    },

    nav: [
      { text: 'Guide', link: '/guide/getting-started', activeMatch: '^/guide/' },
      { text: 'CLI Reference', link: '/cli/', activeMatch: '^/cli/' },
      { text: 'Plugins', link: '/plugins/', activeMatch: '^/plugins/' },
      { text: 'Examples', link: '/examples/multi-repo-workspace', activeMatch: '^/examples/' },
      { text: 'FAQ', link: '/faq/', activeMatch: '^/faq/' }
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Why Repo Nexus?', link: '/guide/why-repo-nexus' },
            { text: 'Virtual Meta-Repo Model', link: '/guide/architecture' },
            { text: 'Two-Level Configuration', link: '/guide/configuration' },
            { text: 'Workflows & Automation', link: '/guide/workflows' }
          ]
        }
      ],
      '/cli/': [
        {
          text: 'CLI Reference',
          items: [
            { text: 'Overview & Global Options', link: '/cli/' },
            { text: 'Workspace Lifecycle', link: '/cli/workspace' },
            { text: 'Member Repositories', link: '/cli/repos' },
            { text: 'Execution (rnex exec)', link: '/cli/execution' },
            { text: 'Tooling & Git Hooks', link: '/cli/tooling' }
          ]
        }
      ],
      '/plugins/': [
        {
          text: 'Plugin Ecosystem',
          items: [
            { text: 'Runtime & Architecture', link: '/plugins/' },
            { text: 'Authoring Custom Plugins', link: '/plugins/authoring' }
          ]
        },
        {
          text: 'Functional Plugins',
          items: [
            { text: 'karpathy-llm (Wiki & Rules)', link: '/plugins/karpathy-llm' }
          ]
        },
        {
          text: 'AI Provider Plugins',
          items: [
            { text: 'Claude Code (CLAUDE.md)', link: '/plugins/claude' },
            { text: 'Cursor (.cursorrules)', link: '/plugins/cursor' },
            { text: 'GitHub Copilot (.github)', link: '/plugins/copilot' },
            { text: 'Google Gemini & Antigravity', link: '/plugins/gemini' },
            { text: 'Windsurf (.windsurfrules)', link: '/plugins/windsurf' }
          ]
        }
      ],
      '/examples/': [
        {
          text: 'Patterns & Use Cases',
          items: [
            { text: 'Fullstack Multi-Repo', link: '/examples/multi-repo-workspace' },
            { text: 'Monorepo Coexistence', link: '/examples/monorepo-coexistence' },
            { text: 'Local Overrides & Offline', link: '/examples/local-overrides' },
            { text: 'Cross-Repo AI Workflows', link: '/examples/ai-workflows' }
          ]
        }
      ],
      '/faq/': [
        {
          text: 'Resources',
          items: [
            { text: 'Frequently Asked Questions', link: '/faq/' }
          ]
        }
      ]
    },

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
      copyright: 'Copyright © 2026 Repo Nexus · MIT License'
    }
  }
})
