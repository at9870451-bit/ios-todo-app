<template>
  <div class="doll-page">
    <div class="doll-stats" v-if="meta">
      <el-card shadow="never" class="stat-card">
        <div class="stat-num">{{ meta.items }}</div>
        <div class="stat-label">服饰款式（启用 {{ meta.enabled_items }}）</div>
      </el-card>
      <el-card shadow="never" class="stat-card">
        <div class="stat-num">{{ meta.outfits }}</div>
        <div class="stat-label">用户穿搭记录（收藏 {{ meta.favorites }}）</div>
      </el-card>
      <el-card shadow="never" class="stat-card">
        <div class="stat-num">{{ meta.ai_calls }}</div>
        <div class="stat-label">AI 调用次数（失败 {{ meta.ai_errors }}）</div>
      </el-card>
    </div>

    <el-card shadow="never">
      <el-tabs v-model="tab">
        <!-- ============ 款式管理 ============ -->
        <el-tab-pane label="服饰款式" name="items">
          <div class="toolbar">
            <el-select v-model="itemQuery.category" placeholder="全部分类" clearable style="width: 150px" @change="loadItems()">
              <el-option v-for="c in categories" :key="c.code" :label="c.name" :value="c.code" />
            </el-select>
            <el-input v-model="itemQuery.keyword" placeholder="名称关键字" clearable style="width: 200px" @keyup.enter="loadItems()" />
            <el-button type="primary" @click="loadItems()">查询</el-button>
            <el-button @click="openItemDialog(null)">新增款式</el-button>
          </div>
          <el-table :data="items" stripe>
            <el-table-column prop="id" label="ID" width="70" />
            <el-table-column label="分类" width="100">
              <template #default="{ row }">{{ catName(row.category) }}</template>
            </el-table-column>
            <el-table-column prop="name" label="名称" min-width="120" />
            <el-table-column prop="style" label="款式键" min-width="110" />
            <el-table-column label="颜色" width="90">
              <template #default="{ row }">
                <span class="color-dot" :style="{ background: row.color }" /> {{ row.color }}
              </template>
            </el-table-column>
            <el-table-column label="3D 模型" min-width="180">
              <template #default="{ row }">
                <el-link v-if="row.model_url" type="primary" :href="row.model_url" target="_blank">{{ shortUrl(row.model_url) }}</el-link>
                <span v-else class="muted">程序化几何</span>
              </template>
            </el-table-column>
            <el-table-column label="启用" width="80">
              <template #default="{ row }">
                <el-switch :model-value="row.enabled" @change="toggleItem(row)" />
              </template>
            </el-table-column>
            <el-table-column label="操作" width="150" fixed="right">
              <template #default="{ row }">
                <el-button link type="primary" @click="openItemDialog(row)">编辑</el-button>
                <el-button link type="danger" @click="removeItem(row)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
          <el-pagination
            class="pager"
            layout="total, prev, pager, next"
            :total="itemTotal"
            :page-size="itemQuery.size"
            :current-page="itemQuery.page"
            @current-change="(p: number) => { itemQuery.page = p; loadItems() }"
          />
        </el-tab-pane>

        <!-- ============ 分类管理 ============ -->
        <el-tab-pane label="服装分类" name="categories">
          <el-table :data="categories" stripe>
            <el-table-column prop="id" label="ID" width="70" />
            <el-table-column prop="code" label="分类码" width="120" />
            <el-table-column prop="name" label="名称" min-width="120">
              <template #default="{ row }">
                <el-input v-model="row.name" size="small" style="max-width: 200px" />
              </template>
            </el-table-column>
            <el-table-column label="排序" width="110">
              <template #default="{ row }">
                <el-input-number v-model="row.sort" size="small" :min="0" :max="999" controls-position="right" style="width: 90px" />
              </template>
            </el-table-column>
            <el-table-column label="款式数" width="90">
              <template #default="{ row }">{{ row.item_count }}</template>
            </el-table-column>
            <el-table-column label="启用" width="80">
              <template #default="{ row }">
                <el-switch v-model="row.enabled" />
              </template>
            </el-table-column>
            <el-table-column label="操作" width="110">
              <template #default="{ row }">
                <el-button link type="primary" @click="saveCategory(row)">保存</el-button>
              </template>
            </el-table-column>
          </el-table>
          <p class="hint">分类码与 App 端 3D 构建器绑定（hair/top/bottom/scarf/hat/shoes/accessory），仅可改名/排序/启停。</p>
        </el-tab-pane>

        <!-- ============ 穿搭记录 ============ -->
        <el-tab-pane label="穿搭记录" name="outfits">
          <div class="toolbar">
            <el-input v-model="outfitQuery.keyword" placeholder="用户 / 搭配名" clearable style="width: 220px" @keyup.enter="loadOutfits()" />
            <el-button type="primary" @click="loadOutfits()">查询</el-button>
          </div>
          <el-table :data="outfits" stripe>
            <el-table-column prop="id" label="ID" width="70" />
            <el-table-column prop="username" label="用户" width="130" />
            <el-table-column prop="name" label="搭配名称" min-width="130" />
            <el-table-column label="性别" width="90">
              <template #default="{ row }">{{ genderName(row.gender) }}</template>
            </el-table-column>
            <el-table-column label="收藏" width="70">
              <template #default="{ row }"><el-tag v-if="row.favorite" type="warning" size="small">已收藏</el-tag></template>
            </el-table-column>
            <el-table-column prop="updated_at" label="更新时间" width="170" />
            <el-table-column label="操作" width="150" fixed="right">
              <template #default="{ row }">
                <el-button link type="primary" @click="viewOutfit(row)">查看搭配</el-button>
                <el-button link type="danger" @click="removeOutfit(row)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
          <el-pagination
            class="pager"
            layout="total, prev, pager, next"
            :total="outfitTotal"
            :page-size="outfitQuery.size"
            :current-page="outfitQuery.page"
            @current-change="(p: number) => { outfitQuery.page = p; loadOutfits() }"
          />
        </el-tab-pane>

        <!-- ============ AI 调用日志 ============ -->
        <el-tab-pane label="AI 调用日志" name="logs">
          <div class="toolbar">
            <el-select v-model="logQuery.status" style="width: 140px" @change="loadLogs()">
              <el-option label="全部" value="all" />
              <el-option label="成功" value="ok" />
              <el-option label="失败" value="error" />
            </el-select>
          </div>
          <el-table :data="logs" stripe>
            <el-table-column prop="id" label="ID" width="70" />
            <el-table-column prop="username" label="用户" width="130" />
            <el-table-column prop="prompt" label="需求" min-width="200" show-overflow-tooltip />
            <el-table-column label="状态" width="90">
              <template #default="{ row }">
                <el-tag :type="row.status === 'ok' ? 'success' : 'danger'" size="small">
                  {{ row.status === 'ok' ? '成功' : '失败' }}
                </el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="duration_ms" label="耗时" width="90">
              <template #default="{ row }">{{ row.duration_ms }} ms</template>
            </el-table-column>
            <el-table-column prop="created_at" label="时间" width="170" />
            <el-table-column label="操作" width="100" fixed="right">
              <template #default="{ row }">
                <el-button link type="primary" @click="viewLog(row)">详情</el-button>
              </template>
            </el-table-column>
          </el-table>
          <el-pagination
            class="pager"
            layout="total, prev, pager, next"
            :total="logTotal"
            :page-size="logQuery.size"
            :current-page="logQuery.page"
            @current-change="(p: number) => { logQuery.page = p; loadLogs() }"
          />
        </el-tab-pane>

        <!-- ============ AI 配置（服务端托管密钥） ============ -->
        <el-tab-pane label="AI 配置" name="ai">
          <el-alert
            type="info"
            :closable="false"
            show-icon
            title="AI 密钥保存在服务端"
            description="App 的 AI 穿搭推荐直接复用服务端已保存的 AI 接口配置（密钥不下发客户端）。用户在 App「对话」页配置的 AI 会出现在此列表。"
            style="margin-bottom: 12px"
          />
          <el-table :data="aiConfigs" stripe>
            <el-table-column prop="id" label="ID" width="70" />
            <el-table-column prop="username" label="用户" width="130" />
            <el-table-column prop="name" label="配置名" min-width="120" />
            <el-table-column prop="model" label="模型" min-width="140" />
            <el-table-column prop="model" label="地址" min-width="0" v-if="false" />
            <el-table-column label="接口地址" min-width="200" show-overflow-tooltip>
              <template #default="{ row }">{{ row.api_url }}</template>
            </el-table-column>
            <el-table-column prop="api_key_masked" label="密钥（掩码）" width="130" />
            <el-table-column label="启用" width="80">
              <template #default="{ row }">
                <el-tag :type="row.enabled ? 'success' : 'info'" size="small">{{ row.enabled ? '启用' : '停用' }}</el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="last_run_at" label="最近使用" width="170" />
          </el-table>
        </el-tab-pane>
      </el-tabs>
    </el-card>

    <!-- 新增/编辑款式 -->
    <el-dialog v-model="itemDialog" :title="itemForm.id ? '编辑款式' : '新增款式'" width="520px">
      <el-form label-width="90px">
        <el-form-item label="分类">
          <el-select v-model="itemForm.category" style="width: 100%" @change="onCatChange">
            <el-option v-for="c in categories" :key="c.code" :label="c.name" :value="c.code" />
          </el-select>
        </el-form-item>
        <el-form-item label="款式键">
          <el-select v-model="itemForm.style" placeholder="选择款式键" style="width: 100%">
            <el-option v-for="s in styleOptions" :key="s" :label="s" :value="s" />
          </el-select>
          <div class="hint">款式键决定 App 端 3D 几何形态，来自构建器内置清单。</div>
        </el-form-item>
        <el-form-item label="名称">
          <el-input v-model="itemForm.name" maxlength="20" />
        </el-form-item>
        <el-form-item label="默认颜色">
          <el-color-picker v-model="itemForm.color" />
          <span style="margin-left: 8px" class="muted">{{ itemForm.color }}</span>
        </el-form-item>
        <el-form-item label="3D 模型">
          <el-upload :show-file-list="false" :http-request="doUpload" accept=".usdz,.glb,.gltf,.reality">
            <el-button :loading="uploading">上传 .usdz / .glb</el-button>
          </el-upload>
          <div class="hint" v-if="itemForm.model_url">已上传：{{ itemForm.model_url }}</div>
          <div class="hint" v-else>可选：上传自定义 3D 模型后覆盖程序化几何；留空使用内置款式。</div>
        </el-form-item>
        <el-form-item label="模型缩放" v-if="itemForm.model_url">
          <el-input-number v-model="itemForm.model_scale" :min="0.01" :max="20" :step="0.1" />
          <span class="hint" style="margin-left: 8px">Y 偏移</span>
          <el-input-number v-model="itemForm.model_offset_y" :min="-2" :max="2" :step="0.05" style="margin-left: 8px" />
        </el-form-item>
        <el-form-item label="排序">
          <el-input-number v-model="itemForm.sort" :min="0" :max="999" />
        </el-form-item>
        <el-form-item label="启用">
          <el-switch v-model="itemForm.enabled" />
        </el-form-item>
        <el-form-item label="会员专属">
          <el-switch v-model="itemForm.premium" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="itemDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="saveItem">保存</el-button>
      </template>
    </el-dialog>

    <!-- 穿搭详情 -->
    <el-dialog v-model="outfitDialog" title="穿搭详情" width="560px">
      <template v-if="outfitDetail">
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="用户">{{ outfitDetail.username }}</el-descriptions-item>
          <el-descriptions-item label="搭配名">{{ outfitDetail.name }}</el-descriptions-item>
          <el-descriptions-item label="性别">{{ genderName(outfitDetail.gender) }}</el-descriptions-item>
          <el-descriptions-item label="肤色">{{ outfitDetail.skin }}</el-descriptions-item>
        </el-descriptions>
        <el-table :data="outfitParts" size="small" style="margin-top: 12px">
          <el-table-column label="分类" width="110">
            <template #default="{ row }">{{ catName(row.category) }}</template>
          </el-table-column>
          <el-table-column prop="style" label="款式键" />
          <el-table-column label="颜色" width="120">
            <template #default="{ row }">
              <span class="color-dot" :style="{ background: row.color }" /> {{ row.color }}
            </template>
          </el-table-column>
        </el-table>
      </template>
    </el-dialog>

    <!-- AI 日志详情 -->
    <el-dialog v-model="logDialog" title="AI 调用详情" width="640px">
      <template v-if="logDetail">
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="用户">{{ logDetail.username }}</el-descriptions-item>
          <el-descriptions-item label="耗时">{{ logDetail.duration_ms }} ms</el-descriptions-item>
          <el-descriptions-item label="时间">{{ logDetail.created_at }}</el-descriptions-item>
          <el-descriptions-item label="状态">{{ logDetail.status }}</el-descriptions-item>
        </el-descriptions>
        <div class="detail-block">
          <div class="detail-label">用户需求</div>
          <pre class="detail-pre">{{ logDetail.prompt }}</pre>
        </div>
        <div class="detail-block">
          <div class="detail-label">AI 返回 / 错误</div>
          <pre class="detail-pre">{{ logDetail.result || logDetail.message }}</pre>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { dollApi } from '@/api'
import type { DollCategoryRow, DollItemRow, DollOutfitRow, DollAiLogRow, DollAiConfigRow, DollMeta } from '@/types'

const tab = ref('items')
const meta = ref<DollMeta | null>(null)
const categories = ref<DollCategoryRow[]>([])

// ------- 款式 -------
const items = ref<DollItemRow[]>([])
const itemTotal = ref(0)
const itemQuery = ref({ page: 1, size: 20, category: '', keyword: '' })

// ------- 穿搭 -------
const outfits = ref<DollOutfitRow[]>([])
const outfitTotal = ref(0)
const outfitQuery = ref({ page: 1, size: 20, keyword: '' })

// ------- 日志 -------
const logs = ref<DollAiLogRow[]>([])
const logTotal = ref(0)
const logQuery = ref({ page: 1, size: 20, status: 'all' })

// ------- AI 配置 -------
const aiConfigs = ref<DollAiConfigRow[]>([])

// ------- 弹窗 -------
const itemDialog = ref(false)
const saving = ref(false)
const uploading = ref(false)
const itemForm = ref<any>({ id: 0, category: 'top', style: 'tee', name: '', color: '#FFFFFF', sort: 0, enabled: true, premium: false, model_url: '', model_scale: 1, model_offset_y: 0 })
const outfitDialog = ref(false)
const outfitDetail = ref<DollOutfitRow | null>(null)
const logDialog = ref(false)
const logDetail = ref<(DollAiLogRow & { result: string }) | null>(null)

const styleOptions = computed(() => meta.value?.styles?.[itemForm.value.category] || [])

function catName(code: string) {
  return categories.value.find((c) => c.code === code)?.name || code
}
function genderName(g: string) {
  return g === 'male' ? '男生' : g === 'female' ? '女生' : '中性'
}
function shortUrl(u: string) {
  return u.length > 26 ? '...' + u.slice(-24) : u
}

const outfitParts = computed(() => {
  if (!outfitDetail.value) return []
  try {
    const st = JSON.parse(outfitDetail.value.state || '{}')
    const items = st.items || {}
    return Object.keys(items).map((k) => ({ category: k, style: items[k].style, color: items[k].color }))
  } catch {
    return []
  }
})

async function loadMeta() {
  const r = await dollApi.meta()
  meta.value = r.data
}
async function loadCategories() {
  const r = await dollApi.categories()
  categories.value = r.data.items
}
async function loadItems() {
  const r = await dollApi.items(itemQuery.value)
  items.value = r.data.items
  itemTotal.value = r.data.total
}
async function loadOutfits() {
  const r = await dollApi.outfits(outfitQuery.value)
  outfits.value = r.data.items
  outfitTotal.value = r.data.total
}
async function loadLogs() {
  const r = await dollApi.aiLogs(logQuery.value)
  logs.value = r.data.items
  logTotal.value = r.data.total
}
async function loadAiConfigs() {
  const r = await dollApi.aiConfigs({ page: 1, size: 100 })
  aiConfigs.value = r.data.items
}

function onCatChange() {
  itemForm.value.style = ''
}
function openItemDialog(row: DollItemRow | null) {
  if (row) {
    itemForm.value = { ...row, model_scale: row.model_scale || 1, model_offset_y: row.model_offset_y || 0 }
  } else {
    itemForm.value = { id: 0, category: itemQuery.value.category || 'top', style: '', name: '', color: '#FFFFFF', sort: 0, enabled: true, premium: false, model_url: '', model_scale: 1, model_offset_y: 0 }
  }
  itemDialog.value = true
}
async function saveItem() {
  if (!itemForm.value.name || !itemForm.value.style) return ElMessage.warning('请填写名称并选择款式键')
  saving.value = true
  try {
    if (itemForm.value.id) {
      await dollApi.updateItem(itemForm.value.id, itemForm.value)
    } else {
      await dollApi.createItem(itemForm.value)
    }
    ElMessage.success('已保存')
    itemDialog.value = false
    await Promise.all([loadItems(), loadMeta()])
  } finally {
    saving.value = false
  }
}
async function toggleItem(row: DollItemRow) {
  await dollApi.updateItem(row.id, { enabled: !row.enabled })
  await loadItems()
}
async function removeItem(row: DollItemRow) {
  await ElMessageBox.confirm(`删除款式「${row.name}」？`, '提示', { type: 'warning' })
  await dollApi.removeItem(row.id)
  ElMessage.success('已删除')
  await Promise.all([loadItems(), loadMeta()])
}
async function doUpload(opt: any) {
  uploading.value = true
  try {
    const r = await dollApi.uploadModel(opt.file)
    itemForm.value.model_url = r.data.url
    ElMessage.success('模型已上传')
  } finally {
    uploading.value = false
  }
}
async function saveCategory(row: DollCategoryRow) {
  await dollApi.updateCategory(row.id, { name: row.name, sort: row.sort, enabled: row.enabled })
  ElMessage.success('分类已更新')
}

function viewOutfit(row: DollOutfitRow) {
  outfitDetail.value = row
  outfitDialog.value = true
}
async function removeOutfit(row: DollOutfitRow) {
  await ElMessageBox.confirm(`删除「${row.username}」的搭配「${row.name}」？`, '提示', { type: 'warning' })
  await dollApi.removeOutfit(row.id)
  ElMessage.success('已删除')
  await loadOutfits()
}
async function viewLog(row: DollAiLogRow) {
  const r = await dollApi.aiLogDetail(row.id)
  logDetail.value = r.data
  logDialog.value = true
}

onMounted(async () => {
  await Promise.all([loadMeta(), loadCategories()])
  await Promise.all([loadItems(), loadOutfits(), loadLogs(), loadAiConfigs()])
})
</script>

<style scoped>
.doll-page { display: flex; flex-direction: column; gap: 14px; }
.doll-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; }
.stat-card { text-align: center; }
.stat-num { font-size: 26px; font-weight: 700; color: #2563eb; }
.stat-label { font-size: 13px; color: #6b7280; margin-top: 4px; }
.toolbar { display: flex; gap: 10px; margin-bottom: 12px; }
.pager { margin-top: 12px; justify-content: flex-end; }
.hint { font-size: 12px; color: #9ca3af; line-height: 1.6; }
.muted { color: #9ca3af; font-size: 12px; }
.color-dot { display: inline-block; width: 12px; height: 12px; border-radius: 3px; border: 1px solid rgba(0, 0, 0, 0.12); vertical-align: -1px; margin-right: 4px; }
.detail-block { margin-top: 12px; }
.detail-label { font-size: 13px; font-weight: 600; margin-bottom: 6px; }
.detail-pre { background: #f8fafc; border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px; font-size: 12px; white-space: pre-wrap; word-break: break-all; max-height: 260px; overflow: auto; }
@media (max-width: 768px) {
  .doll-stats { grid-template-columns: 1fr; }
}
</style>
