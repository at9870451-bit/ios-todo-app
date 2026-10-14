import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes: RouteRecordRaw[] = [
  { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue'), meta: { public: true, title: '登录' } },
  {
    path: '/',
    component: () => import('@/layouts/AdminLayout.vue'),
    children: [
      { path: '', name: 'dashboard', component: () => import('@/views/DashboardView.vue'), meta: { title: '控制台', icon: 'Odometer' } },
      { path: 'users', name: 'users', component: () => import('@/views/UsersView.vue'), meta: { title: '用户管理', icon: 'User', perm: 'users:read' } },
      { path: 'users/:id', name: 'user-detail', component: () => import('@/views/UserDetailView.vue'), meta: { title: '用户详情', perm: 'users:read' } },
      { path: 'doll', name: 'doll', component: () => import('@/views/DollView.vue'), meta: { title: 'Doll Studio', icon: 'MagicStick', perm: 'doll:manage' } },
      { path: 'admins', name: 'admins', component: () => import('@/views/AdminsView.vue'), meta: { title: '管理员与角色', icon: 'UserFilled', perm: 'admins:manage' } },
      { path: 'logs', name: 'logs', component: () => import('@/views/LogsView.vue'), meta: { title: '操作日志', icon: 'Document', perm: 'logs:read' } },
      { path: 'config', name: 'config', component: () => import('@/views/ConfigView.vue'), meta: { title: '系统配置', icon: 'Setting', perm: 'config:manage' } }
    ]
  },
  { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/views/NotFoundView.vue'), meta: { public: true } }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 })
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  document.title = to.meta.title ? `${to.meta.title} · Amore 管理后台` : 'Amore 管理后台'
  if (to.meta.public) {
    if (to.name === 'login' && auth.isLoggedIn) return { path: '/' }
    return true
  }
  if (!auth.isLoggedIn) return { path: '/login', query: { redirect: to.fullPath } }
  if (to.meta.perm && !auth.has(to.meta.perm as string)) return { path: '/' }
  return true
})

export default router
