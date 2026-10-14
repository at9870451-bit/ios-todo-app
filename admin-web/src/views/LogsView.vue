<template>
  <div>
    <h3 class="am-page-title">操作日志</h3>
    <p class="am-page-sub">记录所有管理后台的写操作，用于安全审计</p>

    <div class="am-card">
      <div class="am-toolbar">
        <el-input v-model="query.keyword" placeholder="操作 / 路径 / 管理员 / IP" clearable @keyup.enter="search" />
        <el-date-picker v-model="dateRange" type="daterange" value-format="YYYY-MM-DD"
                        start-placeholder="开始" end-placeholder="结束" style="width:250px" />
        <el-button type="primary" :icon="Search" @click="search">查询</el-button>
        <el-button :icon="Refresh" @click="reset">重置</el-button>
        <div class="am-spacer" style="flex:1" />
        <span style="color:var(--am-text-2);font-size:13px">共 {{ total }} 条</span>
      </div>

      <div class="am-table-wrap">
        <el-table :data="rows" v-loading="loading" stripe size="small">
          <el-table-column prop="id" label="ID" width="80" />
          <el-table-column prop="admin_name" label="管理员" width="120" />
          <el-table-column prop="action" label="操作" width="150" />
          <el-table-column prop="method" label="方法" width="80">
            <template #default="{ row }"><el-tag size="small" effect="plain">{{ row.method }}</el-tag></template>
          </el-table-column>
          <el-table-column prop="path" label="请求路径" min-width="220" show-overflow-tooltip />
          <el-table-column prop="ip" label="IP 地址" width="150" />
          <el-table-column label="状态" width="90">
            <template #default="{ row }">
              <el-tag :type="row.status < 400 ? 'success' : 'danger'" size="small">{{ row.status }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="created_at" label="时间" width="165" />
        </el-table>
      </div>
      <el-empty v-if="!loading && rows.length === 0" description="暂无操作日志" />

      <div class="am-pagination">
        <el-pagination
          v-model:current-page="query.page"
          v-model:page-size="query.size"
          :total="total"
          :page-sizes="[20, 50, 100]"
          layout="total, sizes, prev, pager, next"
          background
          @current-change="load"
          @size-change="load"
        />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { Search, Refresh } from '@element-plus/icons-vue'
import { logApi } from '@/api'
import type { OpLog } from '@/types'

const rows = ref<OpLog[]>([])
const total = ref(0)
const loading = ref(false)
const dateRange = ref<[string, string] | null>(null)
const query = reactive<{ page: number; size: number; keyword: string }>({ page: 1, size: 20, keyword: '' })

async function load() {
  loading.value = true
  try {
    const r = await logApi.list({
      page: query.page, size: query.size, keyword: query.keyword,
      date_from: dateRange.value?.[0], date_to: dateRange.value?.[1]
    })
    rows.value = r.data.items
    total.value = r.data.total
  } finally { loading.value = false }
}
function search() { query.page = 1; load() }
function reset() { query.keyword = ''; query.page = 1; dateRange.value = null; load() }

onMounted(load)
</script>
