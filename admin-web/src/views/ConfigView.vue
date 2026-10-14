<template>
  <div>
    <h3 class="am-page-title">系统配置</h3>
    <p class="am-page-sub">App 运行开关、公告、版本与支付接口配置</p>

    <div class="am-card">
      <el-tabs v-model="tab">
        <!-- 基础配置 -->
        <el-tab-pane label="基础配置" name="basic">
          <el-form :model="cfg" label-width="140px" style="max-width:640px;margin-top:10px" v-loading="cfgLoading">
            <el-form-item label="App 注册开关">
              <el-switch v-model="cfg.register_enabled" active-value="1" inactive-value="0" />
              <span class="hint">关闭后 App 端将无法注册新账号</span>
            </el-form-item>
            <el-form-item label="注册需填写邮箱">
              <el-switch v-model="cfg.register_need_email" active-value="1" inactive-value="0" />
            </el-form-item>
            <el-form-item label="维护模式">
              <el-switch v-model="cfg.maintain_mode" active-value="1" inactive-value="0" />
              <span class="hint">开启后 App 端进入维护提示</span>
            </el-form-item>
            <el-form-item label="站点 / App 名称"><el-input v-model="cfg.site_name" /></el-form-item>
            <el-form-item label="App 当前版本"><el-input v-model="cfg.app_version" /></el-form-item>
            <el-form-item label="App 最低可用版本"><el-input v-model="cfg.min_version" /></el-form-item>
            <el-form-item label="全局公告文本">
              <el-input v-model="cfg.announcement" type="textarea" :rows="3" placeholder="展示在 App 首页的公告文本" />
            </el-form-item>
            <el-form-item>
              <el-button type="primary" :loading="cfgSaving" @click="saveBasic">保存基础配置</el-button>
            </el-form-item>
          </el-form>
        </el-tab-pane>

        <!-- 公告管理 -->
        <el-tab-pane label="公告管理" name="announcement">
          <div class="am-toolbar">
            <div class="am-spacer" style="flex:1" />
            <el-button type="primary" :icon="Plus" @click="openAnnCreate">新增公告</el-button>
          </div>
          <div class="am-table-wrap">
            <el-table :data="anns" v-loading="annLoading" stripe>
              <el-table-column prop="id" label="ID" width="70" />
              <el-table-column prop="title" label="标题" min-width="180" />
              <el-table-column label="类型" width="100">
                <template #default="{ row }"><el-tag size="small" effect="light">{{ annType(row.type) }}</el-tag></template>
              </el-table-column>
              <el-table-column label="状态" width="90">
                <template #default="{ row }">
                  <el-tag :type="row.enabled === 1 ? 'success' : 'info'" size="small">{{ row.enabled === 1 ? '启用' : '停用' }}</el-tag>
                </template>
              </el-table-column>
              <el-table-column prop="start_at" label="开始时间" width="165">
                <template #default="{ row }">{{ row.start_at || '—' }}</template>
              </el-table-column>
              <el-table-column prop="end_at" label="结束时间" width="165">
                <template #default="{ row }">{{ row.end_at || '—' }}</template>
              </el-table-column>
              <el-table-column prop="created_at" label="创建时间" width="165" />
              <el-table-column label="操作" width="140" fixed="right">
                <template #default="{ row }">
                  <el-button link type="primary" size="small" @click="openAnnEdit(row)">编辑</el-button>
                  <el-button link type="danger" size="small" @click="removeAnn(row)">删除</el-button>
                </template>
              </el-table-column>
            </el-table>
          </div>
          <el-empty v-if="!annLoading && anns.length === 0" description="暂无公告" />
        </el-tab-pane>

        <!-- 版本管理 -->
        <el-tab-pane label="版本管理" name="version">
          <div class="am-toolbar">
            <div class="am-spacer" style="flex:1" />
            <el-button type="primary" :icon="Plus" @click="openVerCreate">新增版本</el-button>
          </div>
          <div class="am-table-wrap">
            <el-table :data="vers" v-loading="verLoading" stripe>
              <el-table-column prop="id" label="ID" width="70" />
              <el-table-column prop="platform" label="平台" width="90" />
              <el-table-column prop="version" label="版本号" width="110" />
              <el-table-column prop="build" label="Build" width="90" />
              <el-table-column label="强制更新" width="100">
                <template #default="{ row }">
                  <el-tag :type="row.force_update === 1 ? 'danger' : 'info'" size="small">{{ row.force_update === 1 ? '是' : '否' }}</el-tag>
                </template>
              </el-table-column>
              <el-table-column prop="download_url" label="下载地址" min-width="200" show-overflow-tooltip>
                <template #default="{ row }">{{ row.download_url || '—' }}</template>
              </el-table-column>
              <el-table-column prop="notes" label="更新说明" min-width="160" show-overflow-tooltip>
                <template #default="{ row }">{{ row.notes || '—' }}</template>
              </el-table-column>
              <el-table-column label="状态" width="90">
                <template #default="{ row }">
                  <el-tag :type="row.enabled === 1 ? 'success' : 'info'" size="small">{{ row.enabled === 1 ? '启用' : '停用' }}</el-tag>
                </template>
              </el-table-column>
              <el-table-column label="操作" width="140" fixed="right">
                <template #default="{ row }">
                  <el-button link type="primary" size="small" @click="openVerEdit(row)">编辑</el-button>
                  <el-button link type="danger" size="small" @click="removeVer(row)">删除</el-button>
                </template>
              </el-table-column>
            </el-table>
          </div>
          <el-empty v-if="!verLoading && vers.length === 0" description="暂无版本" />
        </el-tab-pane>

        <!-- API 配置 -->
        <el-tab-pane label="API 配置" name="api">
          <el-form :model="cfg" label-width="140px" style="max-width:640px;margin-top:10px" v-loading="cfgLoading">
            <el-form-item label="支付接口地址"><el-input v-model="cfg.pay_api_url" placeholder="https://..." /></el-form-item>
            <el-form-item label="支付商户号 PID"><el-input v-model="cfg.pay_pid" /></el-form-item>
            <el-form-item label="支付密钥 KEY">
              <el-input v-model="cfg.pay_key" type="password" show-password />
            </el-form-item>
            <el-form-item label="支付开关">
              <el-switch v-model="cfg.pay_enabled" active-value="1" inactive-value="0" />
            </el-form-item>
            <el-form-item>
              <el-button type="primary" :loading="cfgSaving" @click="saveApi">保存 API 配置</el-button>
            </el-form-item>
          </el-form>
        </el-tab-pane>
      </el-tabs>
    </div>

    <!-- 公告对话框 -->
    <el-dialog v-model="annVisible" :title="annForm.id ? '编辑公告' : '新增公告'" width="560px">
      <el-form :model="annForm" label-width="80px">
        <el-form-item label="标题"><el-input v-model="annForm.title" /></el-form-item>
        <el-form-item label="内容"><el-input v-model="annForm.content" type="textarea" :rows="4" /></el-form-item>
        <el-form-item label="类型">
          <el-select v-model="annForm.type" style="width:100%">
            <el-option label="通知" value="notice" />
            <el-option label="活动" value="activity" />
            <el-option label="维护" value="maintain" />
          </el-select>
        </el-form-item>
        <el-form-item label="启用"><el-switch v-model="annForm.enabled" :active-value="1" :inactive-value="0" /></el-form-item>
        <el-form-item label="生效时间">
          <el-date-picker v-model="annRange" type="datetimerange" value-format="YYYY-MM-DD HH:mm:ss"
                          start-placeholder="开始" end-placeholder="结束" style="width:100%" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="annVisible = false">取消</el-button>
        <el-button type="primary" :loading="annSaving" @click="saveAnn">保存</el-button>
      </template>
    </el-dialog>

    <!-- 版本对话框 -->
    <el-dialog v-model="verVisible" :title="verForm.id ? '编辑版本' : '新增版本'" width="560px">
      <el-form :model="verForm" label-width="90px">
        <el-form-item label="平台">
          <el-select v-model="verForm.platform" style="width:100%">
            <el-option label="iOS" value="iOS" />
            <el-option label="Android" value="Android" />
          </el-select>
        </el-form-item>
        <el-form-item label="版本号"><el-input v-model="verForm.version" placeholder="如 3.7" /></el-form-item>
        <el-form-item label="Build"><el-input-number v-model="verForm.build" :min="1" /></el-form-item>
        <el-form-item label="强制更新"><el-switch v-model="verForm.force_update" :active-value="1" :inactive-value="0" /></el-form-item>
        <el-form-item label="下载地址"><el-input v-model="verForm.download_url" placeholder="https://..." /></el-form-item>
        <el-form-item label="更新说明"><el-input v-model="verForm.notes" type="textarea" :rows="3" /></el-form-item>
        <el-form-item label="启用"><el-switch v-model="verForm.enabled" :active-value="1" :inactive-value="0" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="verVisible = false">取消</el-button>
        <el-button type="primary" :loading="verSaving" @click="saveVer">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import { configApi, announcementApi, versionApi } from '@/api'
import type { ConfigMap, Announcement, AppVersion } from '@/types'

const tab = ref('basic')

// 基础 / API 配置共用
const cfg = ref<ConfigMap>({})
const cfgLoading = ref(false)
const cfgSaving = ref(false)
const BASIC_KEYS = ['register_enabled', 'register_need_email', 'maintain_mode', 'site_name', 'app_version', 'min_version', 'announcement']
const API_KEYS = ['pay_api_url', 'pay_pid', 'pay_key', 'pay_enabled']

async function loadConfig() {
  cfgLoading.value = true
  try {
    const r = await configApi.get()
    cfg.value = { register_enabled: '0', register_need_email: '0', maintain_mode: '0', pay_enabled: '0', ...r.data }
  } finally { cfgLoading.value = false }
}
async function saveBasic() {
  cfgSaving.value = true
  try {
    const payload: ConfigMap = {}
    BASIC_KEYS.forEach((k) => (payload[k] = cfg.value[k] ?? ''))
    await configApi.save(payload)
    ElMessage.success('基础配置已保存')
  } finally { cfgSaving.value = false }
}
async function saveApi() {
  cfgSaving.value = true
  try {
    const payload: ConfigMap = {}
    API_KEYS.forEach((k) => (payload[k] = cfg.value[k] ?? ''))
    await configApi.save(payload)
    ElMessage.success('API 配置已保存')
  } finally { cfgSaving.value = false }
}

// 公告
const anns = ref<Announcement[]>([])
const annLoading = ref(false)
const annVisible = ref(false)
const annSaving = ref(false)
const annRange = ref<[string, string] | null>(null)
const annForm = reactive<{ id: number | null; title: string; content: string; type: string; enabled: number }>({
  id: null, title: '', content: '', type: 'notice', enabled: 1
})
const annType = (t: string) => ({ notice: '通知', activity: '活动', maintain: '维护' } as any)[t] || t

async function loadAnns() {
  annLoading.value = true
  try { anns.value = (await announcementApi.list()).data.items } finally { annLoading.value = false }
}
function openAnnCreate() {
  Object.assign(annForm, { id: null, title: '', content: '', type: 'notice', enabled: 1 })
  annRange.value = null
  annVisible.value = true
}
function openAnnEdit(row: Announcement) {
  Object.assign(annForm, { id: row.id, title: row.title, content: row.content, type: row.type, enabled: row.enabled })
  annRange.value = row.start_at && row.end_at ? [row.start_at, row.end_at] : null
  annVisible.value = true
}
async function saveAnn() {
  if (!annForm.title) return ElMessage.warning('请填写标题')
  annSaving.value = true
  const payload: Partial<Announcement> = {
    title: annForm.title, content: annForm.content, type: annForm.type, enabled: annForm.enabled,
    start_at: annRange.value?.[0] || null, end_at: annRange.value?.[1] || null
  }
  try {
    if (annForm.id) await announcementApi.update(annForm.id, payload)
    else await announcementApi.create(payload)
    ElMessage.success('已保存')
    annVisible.value = false
    loadAnns()
  } finally { annSaving.value = false }
}
async function removeAnn(row: Announcement) {
  await ElMessageBox.confirm(`确定删除公告「${row.title}」？`, '删除确认', { type: 'warning' })
  await announcementApi.remove(row.id)
  ElMessage.success('已删除')
  loadAnns()
}

// 版本
const vers = ref<AppVersion[]>([])
const verLoading = ref(false)
const verVisible = ref(false)
const verSaving = ref(false)
const verForm = reactive<Partial<AppVersion>>({ id: undefined, platform: 'iOS', version: '', build: 1, force_update: 0, download_url: '', notes: '', enabled: 1 })

async function loadVers() {
  verLoading.value = true
  try { vers.value = (await versionApi.list()).data.items } finally { verLoading.value = false }
}
function openVerCreate() {
  Object.assign(verForm, { id: undefined, platform: 'iOS', version: '', build: 1, force_update: 0, download_url: '', notes: '', enabled: 1 })
  verVisible.value = true
}
function openVerEdit(row: AppVersion) {
  Object.assign(verForm, { ...row })
  verVisible.value = true
}
async function saveVer() {
  if (!verForm.version) return ElMessage.warning('请填写版本号')
  verSaving.value = true
  try {
    if (verForm.id) await versionApi.update(verForm.id, verForm)
    else await versionApi.create(verForm)
    ElMessage.success('已保存')
    verVisible.value = false
    loadVers()
  } finally { verSaving.value = false }
}
async function removeVer(row: AppVersion) {
  await ElMessageBox.confirm(`确定删除版本 ${row.version}？`, '删除确认', { type: 'warning' })
  await versionApi.remove(row.id)
  ElMessage.success('已删除')
  loadVers()
}

onMounted(() => { loadConfig(); loadAnns(); loadVers() })
</script>

<style scoped>
.hint { color: #94a3b8; font-size: 12px; margin-left: 10px; }
</style>
