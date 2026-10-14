<template>
  <div>
    <h3 class="am-page-title">管理员与角色</h3>
    <p class="am-page-sub">管理后台账号、角色与权限分配</p>

    <!-- 管理员 -->
    <div class="am-card am-mb16">
      <div class="am-toolbar">
        <b>管理员账号</b>
        <div class="am-spacer" style="flex:1" />
        <el-button type="primary" :icon="Plus" @click="openAdminCreate">新增管理员</el-button>
      </div>
      <div class="am-table-wrap">
        <el-table :data="admins" v-loading="adminLoading" stripe>
          <el-table-column prop="id" label="ID" width="70" />
          <el-table-column prop="username" label="用户名" min-width="130" />
          <el-table-column prop="nickname" label="昵称" min-width="120" />
          <el-table-column label="角色" width="140">
            <template #default="{ row }"><el-tag size="small" effect="light">{{ row.role_name }}</el-tag></template>
          </el-table-column>
          <el-table-column label="状态" width="90">
            <template #default="{ row }">
              <el-switch :model-value="row.status === 1" :disabled="row.id === 1"
                         @change="(v:any)=>toggleStatus(row, v)" />
            </template>
          </el-table-column>
          <el-table-column prop="last_login_at" label="最近登录" width="165">
            <template #default="{ row }">{{ row.last_login_at || '—' }}</template>
          </el-table-column>
          <el-table-column prop="last_login_ip" label="登录 IP" width="140">
            <template #default="{ row }">{{ row.last_login_ip || '—' }}</template>
          </el-table-column>
          <el-table-column label="操作" width="210" fixed="right">
            <template #default="{ row }">
              <el-button link type="primary" size="small" @click="openAdminEdit(row)">编辑</el-button>
              <el-button link type="warning" size="small" @click="openAdminReset(row)">重置密码</el-button>
              <el-button link type="danger" size="small" :disabled="row.id === 1 || row.id === auth.admin?.id"
                         @click="removeAdmin(row)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
      </div>
    </div>

    <!-- 角色 -->
    <div class="am-card">
      <div class="am-toolbar">
        <b>角色与权限</b>
        <div class="am-spacer" style="flex:1" />
        <el-button type="primary" :icon="Plus" @click="openRoleCreate">新增角色</el-button>
      </div>
      <div class="am-table-wrap">
        <el-table :data="roles" v-loading="roleLoading" stripe>
          <el-table-column prop="id" label="ID" width="70" />
          <el-table-column prop="name" label="角色名称" width="150" />
          <el-table-column prop="code" label="编码" width="130" />
          <el-table-column label="权限" min-width="300">
            <template #default="{ row }">
              <el-tag v-for="p in row.perms" :key="p" size="small" effect="plain" style="margin:2px 4px 2px 0">
                {{ permLabel(p) }}
              </el-tag>
              <span v-if="!row.perms?.length" style="color:#94a3b8">无</span>
            </template>
          </el-table-column>
          <el-table-column prop="admin_count" label="管理员数" width="100" align="center" />
          <el-table-column prop="remark" label="备注" min-width="140" show-overflow-tooltip />
          <el-table-column label="操作" width="140" fixed="right">
            <template #default="{ row }">
              <el-button link type="primary" size="small" :disabled="row.id === 1" @click="openRoleEdit(row)">编辑</el-button>
              <el-button link type="danger" size="small" :disabled="row.id === 1" @click="removeRole(row)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
      </div>
    </div>

    <!-- 管理员对话框 -->
    <el-dialog v-model="adminVisible" :title="adminForm.id ? '编辑管理员' : '新增管理员'" width="460px">
      <el-form :model="adminForm" label-width="80px">
        <el-form-item label="用户名">
          <el-input v-model="adminForm.username" :disabled="!!adminForm.id" placeholder="3~32 位字母/数字/_@.-" />
        </el-form-item>
        <el-form-item label="昵称"><el-input v-model="adminForm.nickname" /></el-form-item>
        <el-form-item v-if="!adminForm.id" label="密码">
          <el-input v-model="adminForm.password" type="password" show-password placeholder="至少 8 位" />
        </el-form-item>
        <el-form-item label="角色">
          <el-select v-model="adminForm.role_id" style="width:100%">
            <el-option v-for="r in roles" :key="r.id" :label="r.name" :value="r.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="adminVisible = false">取消</el-button>
        <el-button type="primary" :loading="adminSaving" @click="saveAdmin">保存</el-button>
      </template>
    </el-dialog>

    <!-- 管理员重置密码 -->
    <el-dialog v-model="adminResetVisible" title="重置管理员密码" width="420px">
      <el-input v-model="adminResetPwd" type="password" show-password placeholder="新密码（至少 8 位）" />
      <template #footer>
        <el-button @click="adminResetVisible = false">取消</el-button>
        <el-button type="primary" :loading="adminResetLoading" @click="saveAdminReset">确认</el-button>
      </template>
    </el-dialog>

    <!-- 角色对话框 -->
    <el-dialog v-model="roleVisible" :title="roleForm.id ? '编辑角色' : '新增角色'" width="540px">
      <el-form :model="roleForm" label-width="80px">
        <el-form-item label="角色名称"><el-input v-model="roleForm.name" /></el-form-item>
        <el-form-item label="角色编码"><el-input v-model="roleForm.code" :disabled="!!roleForm.id" placeholder="英文标识，如 operator" /></el-form-item>
        <el-form-item label="备注"><el-input v-model="roleForm.remark" /></el-form-item>
        <el-form-item label="权限">
          <div style="width:100%">
            <div v-for="g in PERM_GROUPS" :key="g.name" style="margin-bottom:10px">
              <div style="font-weight:600;font-size:13px;margin-bottom:6px">{{ g.name }}</div>
              <el-checkbox-group v-model="roleForm.perms">
                <el-checkbox v-for="p in g.perms" :key="p" :value="p" :label="p" style="width:170px">
                  {{ permLabel(p) }}
                </el-checkbox>
              </el-checkbox-group>
            </div>
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="roleVisible = false">取消</el-button>
        <el-button type="primary" :loading="roleSaving" @click="saveRole">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import { adminApi, roleApi } from '@/api'
import { useAuthStore } from '@/stores/auth'
import { PERM_GROUPS, PERM_LABELS, type AdminRow, type RoleRow } from '@/types'

const auth = useAuthStore()
const permLabel = (p: string) => PERM_LABELS[p] || p

const admins = ref<AdminRow[]>([])
const adminLoading = ref(false)
const roles = ref<RoleRow[]>([])
const roleLoading = ref(false)

async function loadAdmins() {
  adminLoading.value = true
  try { admins.value = (await adminApi.list()).data.items } finally { adminLoading.value = false }
}
async function loadRoles() {
  roleLoading.value = true
  try { roles.value = (await roleApi.list()).data.items } finally { roleLoading.value = false }
}

// 管理员
const adminVisible = ref(false)
const adminSaving = ref(false)
const adminForm = reactive<{ id: number | null; username: string; nickname: string; password: string; role_id: number }>({
  id: null, username: '', nickname: '', password: '', role_id: 2
})
function openAdminCreate() {
  Object.assign(adminForm, { id: null, username: '', nickname: '', password: '', role_id: roles.value[1]?.id || 2 })
  adminVisible.value = true
}
function openAdminEdit(row: AdminRow) {
  Object.assign(adminForm, { id: row.id, username: row.username, nickname: row.nickname, password: '', role_id: row.role_id })
  adminVisible.value = true
}
async function saveAdmin() {
  if (adminForm.id) {
    adminSaving.value = true
    try {
      await adminApi.update(adminForm.id, { nickname: adminForm.nickname, role_id: adminForm.role_id })
      ElMessage.success('已保存')
      adminVisible.value = false
      loadAdmins()
    } finally { adminSaving.value = false }
    return
  }
  if (adminForm.password.length < 8) return ElMessage.warning('密码至少 8 位')
  adminSaving.value = true
  try {
    await adminApi.create({ username: adminForm.username, nickname: adminForm.nickname, password: adminForm.password, role_id: adminForm.role_id })
    ElMessage.success('已创建')
    adminVisible.value = false
    loadAdmins()
  } finally { adminSaving.value = false }
}
async function toggleStatus(row: AdminRow, v: boolean) {
  await adminApi.update(row.id, { status: v ? 1 : 0 })
  ElMessage.success(v ? '已启用' : '已禁用')
  loadAdmins()
}
const adminResetVisible = ref(false)
const adminResetLoading = ref(false)
const adminResetPwd = ref('')
const adminResetId = ref(0)
function openAdminReset(row: AdminRow) { adminResetId.value = row.id; adminResetPwd.value = ''; adminResetVisible.value = true }
async function saveAdminReset() {
  if (adminResetPwd.value.length < 8) return ElMessage.warning('密码至少 8 位')
  adminResetLoading.value = true
  try {
    await adminApi.resetPassword(adminResetId.value, adminResetPwd.value)
    ElMessage.success('密码已重置')
    adminResetVisible.value = false
  } finally { adminResetLoading.value = false }
}
async function removeAdmin(row: AdminRow) {
  await ElMessageBox.confirm(`确定删除管理员「${row.username}」？`, '删除确认', { type: 'warning' })
  await adminApi.remove(row.id)
  ElMessage.success('已删除')
  loadAdmins()
}

// 角色
const roleVisible = ref(false)
const roleSaving = ref(false)
const roleForm = reactive<{ id: number | null; name: string; code: string; perms: string[]; remark: string }>({
  id: null, name: '', code: '', perms: [], remark: ''
})
function openRoleCreate() {
  Object.assign(roleForm, { id: null, name: '', code: '', perms: [], remark: '' })
  roleVisible.value = true
}
function openRoleEdit(row: RoleRow) {
  Object.assign(roleForm, { id: row.id, name: row.name, code: row.code, perms: [...(row.perms || [])], remark: row.remark })
  roleVisible.value = true
}
async function saveRole() {
  roleSaving.value = true
  try {
    if (roleForm.id) {
      await roleApi.update(roleForm.id, { name: roleForm.name, perms: roleForm.perms, remark: roleForm.remark })
    } else {
      await roleApi.create({ name: roleForm.name, code: roleForm.code, perms: roleForm.perms, remark: roleForm.remark })
    }
    ElMessage.success('已保存')
    roleVisible.value = false
    loadRoles()
  } finally { roleSaving.value = false }
}
async function removeRole(row: RoleRow) {
  await ElMessageBox.confirm(`确定删除角色「${row.name}」？`, '删除确认', { type: 'warning' })
  await roleApi.remove(row.id)
  ElMessage.success('已删除')
  loadRoles()
}

onMounted(() => { loadAdmins(); loadRoles() })
</script>
