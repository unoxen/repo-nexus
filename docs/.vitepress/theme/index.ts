import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import SidebarToggle from './components/SidebarToggle.vue'
import './style.css'
import './custom.css'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'nav-bar-content-after': () => h(SidebarToggle)
    })
  }
}
