<template>
  <div class="am-layout">
    <!-- 侧边栏 -->
    <aside class="am-sidebar" :class="{ collapsed }">
      <div class="am-logo">
        <span class="am-logo-icon">A</span>
        <span v-show="!collapsed">Amore 管理后台</span>
      </div>
      <nav class="am-menu">
        <router-link
          v-for="m in menus"
          :key="m.path"
          :to="m.path"
          class="am-menu-item"
          :class="{ active: isActive(m.path) }"
        >
          <el-icon><component :is="m.icon" /></el-icon>
          <span v-show="!collapsed">{{ m.title }}</span>
        </router-link>
      </nav>
    </aside>

    <!-- 主区 -->
    <div class="am-main">
      <header class="am-header">
        <el-icon class="am-collapse" @click="toggleMenu">
          <Fold v-if="!isMobile && !collapsed" /><Expand v-else-if="!isMobile" /><Menu v-else />
        </el-icon>
        <el-breadcrumb separator="/">
          <el-breadcrumb-item :to="{ path: '/' }">首页</el-breadcrumb-item>
          <el-breadcrumb-item v-if="route.meta.title">{{ route.meta.title }}</el-breadcrumb-item>
        </el-breadcrumb>
        <div class="am-spacer" />
        <el-tag v-if="auth.admin" type="info" effect="plain" size="small">{{ auth.admin.role_name }}</el-tag>
        <el-dropdown trigger="click" @command="onCommand">
          <div class="am-user">
            <el-avatar :size="30" style="background: linear-gradient(135deg,#3b82f6,#2563eb)">
              {{ (auth.admin?.nickname || auth.admin?.username || 'A').charAt(0).toUpperCase() }}
            </el-avatar>
            <span>{{ auth.admin?.nickname || auth.admin?.username }}</span>
            <el-icon><ArrowDown /></el-icon>
          </div>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="password"><el-icon><Key /></el-icon>修改密码</el-dropdown-item>
              <el-dropdown-item command="logout" divided><el-icon><SwitchButton /></el-icon>退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </header>

      <main class="am-content">
        <router-view v-slot="{ Component }">
          <keep-alive :include="['DashboardView']">
            <component :is="Component" />
          </keep-alive>
        </router-view>
      </main>
    </div>

    <!-- 移动端抽屉 -->
    <el-drawer v-model="drawer" direction="ltr" size="226px" :with-header="false">
      <div style="background: linear-gradient(180deg,#0b1f3a,#14315f); min-height:100%; margin:-20px; padding:20px 0">
        <div class="am-logo" style="color:#fff"><span class="am-logo-icon">A</span><span>Amore 管理后台</span></div>
        <nav class="am-menu">
          <router-link
            v-for="m in menus" :key="m.path" :to="m.path" class="am-menu-item"
            :class="{ active: isActive(m.path) }" @click="drawer = false"
          >
            <el-icon><component :is="m.icon" /></el-icon><span>{{ m.title }}</span>
          </router-link>
        </nav>
      </div>
    </el-drawer>

    <!-- 修改密码 -->
    <el-dialog v-model="pwVisible" title="修改密码" width="420px">
      <el-form :model="pwForm" label-width="90px">
        <el-form-item label="原密码"><el-input v-model="pwForm.old_password" type="password" show-password /></el-form-item>
        <el-form-item label="新密码"><el-input v-model="pwForm.new_password" type="password" show-password placeholder="至少 8 位" /></el-form-item>
        <el-form-item label="确认新密码"><el-input v-model="pwForm.confirm" type="password" show-password /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="pwVisible = false">取消</el-button>
        <el-button type="primary" :loading="pwLoading" @click="submitPassword">确定</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useAuthStore } from '@/stores/auth'
import { authApi } from '@/api'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

const collapsed = ref(false)
const drawer = ref(false)
const isMobile = ref(window.innerWidth <= 768)

const menus = computed(() => {
  const all = [
    { path: '/', title: '控制台', icon: 'Odometer', perm: '' },
    { path: '/users', title: '用户管理', icon: 'User', perm: 'users:read' },
    { path: '/admins', title: '管理员与角色', icon: 'UserFilled', perm: 'admins:manage' },
    { path: '/logs', title: '操作日志', icon: 'Document', perm: 'logs:read' },
    { path: '/config', title: '系统配置', icon: 'Setting', perm: 'config:manage' }
  ]
  return all.filter((m) => !m.perm || auth.has(m.perm))
})

function isActive(path: string) {
  if (path === '/') return route.path === '/'
  return route.path.startsWith(path)
}

function toggleMenu() {
  if (isMobile.value) drawer.value = !drawer.value
  else collapsed.value = !collapsed.value
}

function onResize() {
  isMobile.value = window.innerWidth <= 768
}
onMounted(() => {
  window.addEventListener('resize', onResize)
  auth.refresh().catch(() => {})
})

const pwVisible = ref(false)
const pwLoading = ref(false)
const pwForm = ref({ old_password: '', new_password: '', confirm: '' })

async function onCommand(cmd: string) {
  if (cmd === 'password') { pwForm.value = { old_password: '', new_password: '', confirm: '' }; pwVisible.value = true }
  if (cmd === 'logout') {
    await ElMessageBox.confirm('确定退出登录？', '提示', { type: 'warning' })
    await auth.logout()
    ElMessage.success('已退出')
    router.push('/login')
  }
}

async function submitPassword() {
  if (pwForm.value.new_password.length < 8) return ElMessage.warning('新密码至少 8 位')
  if (pwForm.value.new_password !== pwForm.value.confirm) return ElMessage.warning('两次输入的密码不一致')
  pwLoading.value = true
  try {
    await authApi.password(pwForm.value.old_password, pwForm.value.new_password)
    ElMessage.success('密码已修改')
    pwVisible.value = false
  } finally { pwLoading.value = false }
}
</script>
