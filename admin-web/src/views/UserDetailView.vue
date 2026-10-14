<template>
  <div v-loading="loading">
    <div class="am-toolbar">
      <el-button :icon="ArrowLeft" @click="$router.back()">返回</el-button>
      <h3 class="am-page-title" style="margin:0">用户详情</h3>
    </div>

    <!-- 头部 -->
    <div class="am-card am-mb16">
      <div class="am-profile">
        <div class="am-avatar">{{ (user?.nickname || user?.username || '?').charAt(0).toUpperCase() }}</div>
        <div style="flex:1;min-width:220px">
          <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
            <span style="font-size:20px;font-weight:700">{{ user?.username }}</span>
            <span v-if="user?.nickname" style="color:var(--am-text-2)">{{ user.nickname }}</span>
            <el-tag :type="levelColor(user?.level || '')" size="small">{{ levelLabel(user?.level || '') }}</el-tag>
            <el-tag :type="user?.status === 1 ? 'success' : 'danger'" size="small" effect="dark">
              {{ user?.status === 1 ? '正常' : '封禁' }}
            </el-tag>
            <el-tag v-if="user?.role === 'admin'" type="warning" size="small">管理员</el-tag>
          </div>
          <div class="am-profile-meta" style="margin-top:10px">
            <div>用户 ID：<b>{{ user?.id }}</b></div>
            <div>邮箱：<b>{{ user?.email || '—' }}</b></div>
            <div>注册时间：<b>{{ user?.created_at || '—' }}</b></div>
            <div>最近登录：<b>{{ user?.last_login_at || '—' }}</b></div>
            <div>注册 IP：<b>{{ user?.register_ip || '—' }}</b></div>
            <div>最近登录 IP：<b>{{ user?.last_login_ip || '—' }}</b></div>
          </div>
          <el-alert v-if="user?.status === 0" type="error" :closable="false" style="margin-top:10px"
                    :title="`封禁原因：${user?.ban_reason || '未填写'}${user?.ban_until ? '（至 ' + user.ban_until + '）' : '（永久）'}`" />
        </div>
        <div style="display:flex;gap:8px">
          <el-button v-if="auth.has('users:ban') && user?.status === 1" type="danger" @click="openBan">封禁</el-button>
          <el-button v-if="auth.has('users:ban') && user?.status === 0" type="success" @click="doUnban">解封</el-button>
          <el-button v-if="auth.has('users:resetpw')" @click="resetVisible = true">重置密码</el-button>
        </div>
      </div>
    </div>

    <!-- 统计 -->
    <div class="am-grid am-stat-grid am-mb16">
      <div class="am-card" v-for="s in statCards" :key="s.label">
        <div class="am-stat">
          <div class="am-stat-icon" :class="s.grad"><el-icon><component :is="s.icon" /></el-icon></div>
          <div><div class="am-stat-val">{{ s.value }}</div><div class="am-stat-label">{{ s.label }}</div></div>
        </div>
      </div>
    </div>

    <!-- Tabs -->
    <div class="am-card">
      <el-tabs v-model="tab">
        <el-tab-pane label="登录记录" name="logins">
          <div class="am-table-wrap">
            <el-table :data="logins" v-loading="logLoading" size="small" stripe>
              <el-table-column prop="ip" label="IP 地址" width="150" />
              <el-table-column prop="device_model" label="设备型号" width="130">
                <template #default="{ row }">{{ row.device_model || '—' }}</template>
              </el-table-column>
              <el-table-column prop="os_version" label="系统版本" width="110">
                <template #default="{ row }">{{ row.os_version || '—' }}</template>
              </el-table-column>
              <el-table-column prop="app_version" label="App 版本" width="100">
                <template #default="{ row }">{{ row.app_version || '—' }}</template>
              </el-table-column>
              <el-table-column prop="ua" label="User-Agent" min-width="220" show-overflow-tooltip>
                <template #default="{ row }">{{ row.ua || '—' }}</template>
              </el-table-column>
              <el-table-column label="结果" width="80">
                <template #default="{ row }">
                  <el-tag :type="row.success === 1 ? 'success' : 'danger'" size="small">{{ row.success === 1 ? '成功' : '失败' }}</el-tag>
                </template>
              </el-table-column>
              <el-table-column prop="created_at" label="时间" width="165" />
            </el-table>
          </div>
          <el-empty v-if="!logLoading && logins.length === 0" description="暂无登录记录" />
          <div class="am-pagination" v-if="logTotal > logQuery.size">
            <el-pagination v-model:current-page="logQuery.page" :page-size="logQuery.size" :total="logTotal"
                           layout="prev, pager, next" background @current-change="loadLogins" />
          </div>
        </el-tab-pane>

        <el-tab-pane label="设备信息" name="devices">
          <div class="am-table-wrap">
            <el-table :data="devices" v-loading="devLoading" size="small" stripe>
              <el-table-column prop="device_id" label="设备标识" min-width="200" show-overflow-tooltip />
              <el-table-column prop="device_model" label="设备型号" width="150">
                <template #default="{ row }">{{ row.device_model || '—' }}</template>
              </el-table-column>
              <el-table-column prop="os_version" label="系统版本" width="120">
                <template #default="{ row }">{{ row.os_version || '—' }}</template>
              </el-table-column>
              <el-table-column prop="app_version" label="App 版本" width="110">
                <template #default="{ row }">{{ row.app_version || '—' }}</template>
              </el-table-column>
              <el-table-column prop="last_seen_at" label="最近活跃" width="165" />
              <el-table-column prop="created_at" label="首次出现" width="165" />
            </el-table>
          </div>
          <el-empty v-if="!devLoading && devices.length === 0" description="暂无设备信息" />
        </el-tab-pane>

        <el-tab-pane label="账号变更记录" name="changes">
          <div class="am-table-wrap">
            <el-table :data="changes" v-loading="chgLoading" size="small" stripe>
              <el-table-column prop="field" label="字段" width="120">
                <template #default="{ row }">{{ fieldLabel(row.field) }}</template>
              </el-table-column>
              <el-table-column prop="old_value" label="原值" min-width="160" show-overflow-tooltip>
                <template #default="{ row }">{{ row.old_value || '—' }}</template>
              </el-table-column>
              <el-table-column prop="new_value" label="新值" min-width="160" show-overflow-tooltip>
                <template #default="{ row }">{{ row.new_value || '—' }}</template>
              </el-table-column>
              <el-table-column prop="operator" label="操作者" width="120" />
              <el-table-column prop="source" label="来源" width="110">
                <template #default="{ row }">
                  <el-tag size="small" effect="plain">{{ sourceLabel(row.source) }}</el-tag>
                </template>
              </el-table-column>
              <el-table-column prop="created_at" label="时间" width="165" />
            </el-table>
          </div>
          <el-empty v-if="!chgLoading && changes.length === 0" description="暂无变更记录" />
          <div class="am-pagination" v-if="chgTotal > chgQuery.size">
            <el-pagination v-model:current-page="chgQuery.page" :page-size="chgQuery.size" :total="chgTotal"
                           layout="prev, pager, next" background @current-change="loadChanges" />
          </div>
        </el-tab-pane>
      </el-tabs>
    </div>

    <!-- 封禁 -->
    <el-dialog v-model="banVisible" title="封禁用户" width="440px">
      <el-form label-width="80px">
        <el-form-item label="用户"><b>{{ user?.username }}</b></el-form-item>
        <el-form-item label="封禁原因"><el-input v-model="banForm.reason" type="textarea" :rows="3" /></el-form-item>
        <el-form-item label="封禁时长">
          <el-select v-model="banForm.days" style="width:100%">
            <el-option label="永久封禁" :value="0" />
            <el-option v-for="d in [1,3,7,30]" :key="d" :label="`${d} 天`" :value="d" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="banVisible = false">取消</el-button>
        <el-button type="danger" :loading="banLoading" @click="doBan">确认封禁</el-button>
      </template>
    </el-dialog>

    <!-- 重置密码 -->
    <el-dialog v-model="resetVisible" title="重置用户密码" width="420px">
      <el-input v-model="resetPwd" type="password" show-password placeholder="新密码（至少 8 位）" />
      <template #footer>
        <el-button @click="resetVisible = false">取消</el-button>
        <el-button type="primary" :loading="resetLoading" @click="doReset">确认重置</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { ArrowLeft } from '@element-plus/icons-vue'
import { userApi } from '@/api'
import { useAuthStore } from '@/stores/auth'
import { LEVELS, type UserRow, type UserStats, type LoginLog, type DeviceInfo, type ChangeLog } from '@/types'

const route = useRoute()
const auth = useAuthStore()
const id = Number(route.params.id)

const loading = ref(false)
const user = ref<UserRow | null>(null)
const stats = ref<UserStats>({ sessions: 0, messages: 0, ai_configs: 0, strategies: 0, orders: 0 })
const tab = ref('logins')

const levelLabel = (v: string) => LEVELS.find((l) => l.value === v)?.label || v
const levelColor = (v: string) => LEVELS.find((l) => l.value === v)?.color || 'info'
const fieldLabel = (f: string) => ({ nickname: '昵称', email: '邮箱', status: '账号状态', level: '会员等级', password: '密码' } as any)[f] || f
const sourceLabel = (s: string) => ({ console: '管理后台', ios: 'App', 'ios-admin': 'App 管理页' } as any)[s] || s

const statCards = computed(() => [
  { label: '会话数', value: stats.value.sessions, icon: 'ChatDotRound', grad: 'grad-blue' },
  { label: '消息数', value: stats.value.messages, icon: 'Message', grad: 'grad-cyan' },
  { label: 'AI 配置', value: stats.value.ai_configs, icon: 'MagicStick', grad: 'grad-green' },
  { label: '策略数', value: stats.value.strategies, icon: 'TrendCharts', grad: 'grad-violet' },
  { label: '订单数', value: stats.value.orders, icon: 'ShoppingCart', grad: 'grad-orange' }
])

async function loadDetail() {
  loading.value = true
  try {
    const r = await userApi.detail(id)
    user.value = r.data.user
    stats.value = r.data.stats
  } finally { loading.value = false }
}

const logins = ref<LoginLog[]>([])
const logTotal = ref(0)
const logLoading = ref(false)
const logQuery = reactive({ page: 1, size: 20 })
async function loadLogins() {
  logLoading.value = true
  try {
    const r = await userApi.logins(id, logQuery.page, logQuery.size)
    logins.value = r.data.items
    logTotal.value = r.data.total
  } finally { logLoading.value = false }
}

const devices = ref<DeviceInfo[]>([])
const devLoading = ref(false)
async function loadDevices() {
  devLoading.value = true
  try {
    const r = await userApi.devices(id)
    devices.value = r.data.items
  } finally { devLoading.value = false }
}

const changes = ref<ChangeLog[]>([])
const chgTotal = ref(0)
const chgLoading = ref(false)
const chgQuery = reactive({ page: 1, size: 20 })
async function loadChanges() {
  chgLoading.value = true
  try {
    const r = await userApi.changes(id, chgQuery.page, chgQuery.size)
    changes.value = r.data.items
    chgTotal.value = r.data.total
  } finally { chgLoading.value = false }
}

// 封禁/解封/重置
const banVisible = ref(false)
const banLoading = ref(false)
const banForm = reactive({ reason: '', days: 0 })
function openBan() { banForm.reason = ''; banForm.days = 0; banVisible.value = true }
async function doBan() {
  banLoading.value = true
  try {
    await userApi.ban(id, banForm.reason, banForm.days)
    ElMessage.success('已封禁')
    banVisible.value = false
    await Promise.all([loadDetail(), loadChanges()])
  } finally { banLoading.value = false }
}
async function doUnban() {
  await ElMessageBox.confirm('确定解封该用户？', '解封确认', { type: 'warning' })
  await userApi.unban(id)
  ElMessage.success('已解封')
  await Promise.all([loadDetail(), loadChanges()])
}

const resetVisible = ref(false)
const resetLoading = ref(false)
const resetPwd = ref('')
async function doReset() {
  if (resetPwd.value.length < 8) return ElMessage.warning('新密码至少 8 位')
  resetLoading.value = true
  try {
    await userApi.resetPassword(id, resetPwd.value)
    ElMessage.success('密码已重置')
    resetVisible.value = false
  } finally { resetLoading.value = false }
}

onMounted(() => { loadDetail(); loadLogins(); loadDevices(); loadChanges() })
</script>
