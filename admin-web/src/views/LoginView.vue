<template>
  <div class="am-login-wrap">
    <div class="am-login-card">
      <div class="am-login-head">
        <h2>Amore 管理后台</h2>
        <p>iOS App 用户与运营管理控制台</p>
      </div>
      <div class="am-login-body">
        <el-form :model="form" @submit.prevent="submit" size="large">
          <el-form-item>
            <el-input v-model="form.username" placeholder="管理员账号" :prefix-icon="User" clearable />
          </el-form-item>
          <el-form-item>
            <el-input v-model="form.password" type="password" placeholder="密码" :prefix-icon="Lock"
                      show-password @keyup.enter="submit" />
          </el-form-item>
          <el-button type="primary" size="large" style="width:100%" :loading="loading" @click="submit">
            登 录
          </el-button>
        </el-form>
        <p style="text-align:center;color:#94a3b8;font-size:12px;margin:18px 0 0">
          受保护的系统，仅限授权管理员访问
        </p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { User, Lock } from '@element-plus/icons-vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()
const loading = ref(false)
const form = ref({ username: '', password: '' })

async function submit() {
  if (!form.value.username || !form.value.password) return ElMessage.warning('请输入账号和密码')
  loading.value = true
  try {
    await auth.login(form.value.username, form.value.password)
    ElMessage.success('登录成功')
    const redirect = (route.query.redirect as string) || '/'
    router.push(redirect)
  } catch {
    /* 错误已在拦截器提示 */
  } finally {
    loading.value = false
  }
}
</script>
