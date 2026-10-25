<script setup lang="ts">
import { ref, onMounted } from 'vue'

const isCollapsed = ref(false)

onMounted(() => {
  try {
    const stored = sessionStorage.getItem('rnex-sidebar-collapsed')
    if (stored === 'true') {
      isCollapsed.value = true
      document.body.classList.add('rnex-sidebar-collapsed')
    } else {
      isCollapsed.value = false
      document.body.classList.remove('rnex-sidebar-collapsed')
    }
  } catch (e) {
    // Graceful fallback if storage is restricted
  }
})

function toggleSidebar() {
  isCollapsed.value = !isCollapsed.value
  try {
    if (isCollapsed.value) {
      document.body.classList.add('rnex-sidebar-collapsed')
      sessionStorage.setItem('rnex-sidebar-collapsed', 'true')
    } else {
      document.body.classList.remove('rnex-sidebar-collapsed')
      sessionStorage.setItem('rnex-sidebar-collapsed', 'false')
    }
  } catch (e) {
    // Graceful fallback
  }
}
</script>

<template>
  <button
    type="button"
    class="rnex-sidebar-toggle-btn"
    :title="isCollapsed ? 'Show left sidebar' : 'Hide left sidebar'"
    :aria-label="isCollapsed ? 'Show left sidebar' : 'Hide left sidebar'"
    :aria-pressed="isCollapsed"
    @click="toggleSidebar"
  >
    <!-- Icon when expanded (click to collapse sidebar) -->
    <svg
      v-if="!isCollapsed"
      class="rnex-toggle-icon"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
      <line x1="9" y1="3" x2="9" y2="21" />
      <path d="M14 9l-3 3 3 3" />
    </svg>

    <!-- Icon when collapsed (click to expand sidebar) -->
    <svg
      v-else
      class="rnex-toggle-icon"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
      <line x1="9" y1="3" x2="9" y2="21" />
      <path d="M12 9l3 3-3 3" />
    </svg>
  </button>
</template>

<style scoped>
.rnex-sidebar-toggle-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  color: var(--vp-c-text-2);
  background: transparent;
  border: 1px solid transparent;
  cursor: pointer;
  margin-left: 8px;
  transition: color 0.2s, background-color 0.2s, border-color 0.2s;
}

.rnex-sidebar-toggle-btn:hover {
  color: var(--vp-c-brand-1);
  background-color: var(--vp-c-bg-mute);
  border-color: var(--vp-c-divider);
}

.rnex-toggle-icon {
  width: 18px;
  height: 18px;
}

/* Hide toggle on small screens where sidebar is a mobile drawer */
@media (max-width: 959px) {
  .rnex-sidebar-toggle-btn {
    display: none;
  }
}
</style>
