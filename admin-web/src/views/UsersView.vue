<template>
  <div>
    <h3 class="am-page-title">用户管理</h3>
    <p class="am-page-sub">查看、搜索、筛选 App 注册用户，支持封禁 / 解封与密码重置</p>

    <div class="am-card am-mb16">
      <div class="am-toolbar">
        <el-input v-model="query.keyword" placeholder="用户名 / 昵称 / 邮箱 / ID" clearable @keyup.enter="search" />
        <el-select v-model="query.status" placeholder="账号状态" clearable style="width:130px">
          <el-option label="全部状态" value="" />
          <el-option label="正常" value="1" />
          <el-option label="封禁" value="0" />
        </el-select>
        <el-select v-model="query.level" placeholder="会员等级" clearable style="width:130px">
          <el-option label="全部等级" value="" />
          <el-option v-for="l in LEVELS" :key="l.value" :label="l.label" :value="l.value" />
        </el-select>
        <el-date-picker v-model="dateRange" type="daterange" value-format="YYYY-MM-DD"
                        start-placeholder="注册起" end-placeholder="注册止" style="width:250px" />
        <el-button type="primary" :icon="Search" @click="search">查询</el-button>
        <el-button :icon="Refresh" @click="reset">重置</el-button>
        <div class="am-spacer" style="flex:1" />
        <span style="color:var(--am-text-2);font-size:13px">共 {{ total }} 位用户</span>
      </div>

      <div class="am-table-wrap">
        <el-table :data="rows" v-loading="loading" stripe @row-click="(r:any)=>goDetail(r.id)">
          <el-table-column prop="id" label="ID" width="80" />
          <el-table-column prop="username" label="用户名" min-width="130" show-overflow-tooltip />
          <el-table-column prop="nickname" label="昵称" min-width="120" show-overflow-tooltip />
          <el-table-column prop="email" label="邮箱" min-width="180" show-overflow-tooltip>
            <template #default="{ row }">{{ row.email || '—' }}</template>
          </el-table-column>
          <el-table-column label="会员等级" width="110">
            <template #default="{ row }">
              <el-tag :type="levelColor(row.level)" effect="light" size="small">{{ levelLabel(row.level) }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column label="状态" width="90">
            <template #default="{ row }">
              <el-tag :type="row.status === 1 ? 'success' : 'danger'" size="small" effect="dark">
                {{ row.status === 1 ? '正常' : '封禁' }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="created_at" label="注册时间" width="165" />
          <el-table-column label="最近登录" width="165">
            <template #default="{ row }">{{ row.last_login_at || '—' }}</template>
          </el-table-column>
          <el-table-column label="操作" width="230" fixed="right">
            <template #default="{ row }">
              <el-button link type="primary" size="small" @click.stop="goDetail(row.id)">详情</el-button>
              <el-button v-if="auth.has('users:ban')" link :type="row.status === 1 ? 'danger' : 'success'"
                         size="small" @click.stop="row.status === 1 ? openBan(row) : doUnban(row)">
                {{ row.status === 1 ? '封禁' : '解封' }}
              </el-button>
              <el-button v-if="auth.has('users:resetpw')" link type="warning" size="small"
                         @click.stop="openReset(row)">重置密码</el-button>
            </template>
          </el-table-column>
        </el-table>
      </div>

      <div class="am-pagination">
        <el-pagination
          v-model:current-page="query.page"
          v-model:page-size="query.size"
          :total="total"
          :page-sizes="[10, 20, 50, 100]"
          layout="total, sizes, prev, pager, next, jumper"
          background
          @current-change="load"
          @size-change="load"
        />
      </div>
    </div>

    <!-- 封禁 -->
    <el-dialog v-model="banVisible" title="封禁用户" width="440px">
      <el-form label-width="80px">
        <el-form-item label="用户"><b>{{ current?.username }}</b> (ID {{ current?.id }})</el-form-item>
        <el-form-item label="封禁原因">
          <el-input v-model="banForm.reason" type="textarea" :rows="3" placeholder="请填写封禁原因（将展示给用户）" />
        </el-form-item>
        <el-form-item label="封禁时长">
          <el-select v-model="banForm.days" style="width:100%">
            <el-option label="永久封禁" :value="0" />
            <el-option label="1 天" :value="1" />
            <el-option label="3 天" :value="3" />
            <el-option label="7 天" :value="7" />
            <el-option label="30 天" :value="30" />
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
      <el-form label-width="80px">
        <el-form-item label="用户"><b>{{ current?.username }}</b></el-form-item>
        <el-form-item label="新密码">
          <el-input v-model="resetPwd" type="password" show-password placeholder="至少 8 位" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="resetVisible = false">取消</el-button>
        <el-button type="primary" :loading="resetLoading" @click="doReset">确认重置</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Search, Refresh } from '@element-plus/icons-vue'
import { userApi, type UserQuery } from '@/api'
import { useAuthStore } from '@/stores/auth'
import { LEVELS, type UserRow } from '@/types'

const router = useRouter()
const auth = useAuthStore()

const rows = ref<UserRow[]>([])
const total = ref(0)
const loading = ref(false)
const dateRange = ref<[string, string] | null>(null)

const query = reactive<UserQuery>({ page: 1, size: 20, keyword: '', status: '', level: '', order: 'created_at', dir: 'desc' })

function levelLabel(v: string) { return LEVELS.find((l) => l.value === v)?.label || v }
function levelColor(v: string) { return LEVELS.find((l) => l.value === v)?.color || 'info' }

async function load() {
  loading.value = true
  try {
    const r = await userApi.list({
      ...query,
      date_from: dateRange.value?.[0],
      date_to: dateRange.value?.[1]
    })
    rows.value = r.data.items
    total.value = r.data.total
  } finally { loading.value = false }
}

function search() { query.page = 1; load() }
function reset() {
  query.keyword = ''; query.status = ''; query.level = ''; query.page = 1; dateRange.value = null
  load()
}

function goDetail(id: number) { router.push(`/users/${id}`) }

// 封禁
const banVisible = ref(false)
const banLoading = ref(false)
const current = ref<UserRow | null>(null)
const banForm = reactive({ reason: '', days: 0 })

function openBan(row: UserRow) {
  current.value = row
  banForm.reason = ''
  banForm.days = 0
  banVisible.value = true
}
async function doBan() {
  if (!current.value) return
  banLoading.value = true
  try {
    await userApi.ban(current.value.id, banForm.reason, banForm.days)
    ElMessage.success('已封禁')
    banVisible.value = false
    load()
  } finally { banLoading.value = false }
}
async function doUnban(row: UserRow) {
  await ElMessageBox.confirm(`确定解封用户「${row.username}」？`, '解封确认', { type: 'warning' })
  await userApi.unban(row.id)
  ElMessage.success('已解封')
  load()
}

// 重置密码
const resetVisible = ref(false)
const resetLoading = ref(false)
const resetPwd = ref('')
function openReset(row: UserRow) { current.value = row; resetPwd.value = ''; resetVisible.value = true }
async function doReset() {
  if (!current.value) return
  if (resetPwd.value.length < 8) return ElMessage.warning('新密码至少 8 位')
  resetLoading.value = true
  try {
    await userApi.resetPassword(current.value.id, resetPwd.value)
    ElMessage.success('密码已重置')
    resetVisible.value = false
  } finally { resetLoading.value = false }
}

onMounted(load)
</script>
