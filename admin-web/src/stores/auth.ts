import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '@/api'
import { TOKEN_KEY, ADMIN_KEY } from '@/api/client'
import type { AdminInfo } from '@/types'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string>(localStorage.getItem(TOKEN_KEY) || '')
  const admin = ref<AdminInfo | null>(JSON.parse(localStorage.getItem(ADMIN_KEY) || 'null'))

  const isLoggedIn = computed(() => !!token.value)
  const perms = computed(() => admin.value?.perms || [])
  const isSuper = computed(() => admin.value?.role_code === 'superadmin')

  function has(perm: string) {
    return isSuper.value || perms.value.includes(perm)
  }

  function persist() {
    localStorage.setItem(TOKEN_KEY, token.value)
    localStorage.setItem(ADMIN_KEY, JSON.stringify(admin.value))
  }

  async function login(username: string, password: string) {
    const resp = await authApi.login(username, password)
    const data = resp.data
    token.value = data.token || ''
    admin.value = data
    persist()
    return data
  }

  async function refresh() {
    const resp = await authApi.me()
    admin.value = resp.data
    persist()
  }

  async function logout() {
    try { await authApi.logout() } catch { /* ignore */ }
    token.value = ''
    admin.value = null
    localStorage.removeItem(TOKEN_KEY)
    localStorage.removeItem(ADMIN_KEY)
  }

  return { token, admin, isLoggedIn, perms, isSuper, has, login, refresh, logout }
})
