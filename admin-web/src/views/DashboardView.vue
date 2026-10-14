<template>
  <div>
    <h3 class="am-page-title">控制台</h3>
    <p class="am-page-sub">实时掌握 App 用户增长与活跃情况</p>

    <!-- 统计卡片 -->
    <div class="am-grid am-stat-grid am-mb16">
      <div class="am-card">
        <div class="am-stat">
          <div class="am-stat-icon grad-blue"><el-icon><User /></el-icon></div>
          <div>
            <div class="am-stat-val">{{ fmt(ov.user_total) }}</div>
            <div class="am-stat-label">总用户数</div>
          </div>
        </div>
      </div>
      <div class="am-card">
        <div class="am-stat">
          <div class="am-stat-icon grad-cyan"><el-icon><Plus /></el-icon></div>
          <div>
            <div class="am-stat-val">{{ fmt(ov.user_today) }}</div>
            <div class="am-stat-label">今日注册 · 昨日 {{ fmt(ov.user_yesterday) }}</div>
          </div>
        </div>
      </div>
      <div class="am-card">
        <div class="am-stat">
          <div class="am-stat-icon grad-green"><el-icon><TrendCharts /></el-icon></div>
          <div>
            <div class="am-stat-val">{{ fmt(ov.active_week) }}</div>
            <div class="am-stat-label">7 日活跃用户</div>
          </div>
        </div>
      </div>
      <div class="am-card">
        <div class="am-stat">
          <div class="am-stat-icon grad-orange"><el-icon><DataLine /></el-icon></div>
          <div>
            <div class="am-stat-val">{{ fmt(ov.active_month) }}</div>
            <div class="am-stat-label">30 日活跃用户</div>
          </div>
        </div>
      </div>
    </div>

    <!-- 趋势图 -->
    <div class="am-card am-mb16">
      <div class="am-toolbar">
        <b>注册与活跃趋势</b>
        <div class="am-spacer" style="flex:1" />
        <el-radio-group v-model="trendDays" size="small" @change="loadTrend">
          <el-radio-button :value="7">7 天</el-radio-button>
          <el-radio-button :value="14">14 天</el-radio-button>
          <el-radio-button :value="30">30 天</el-radio-button>
        </el-radio-group>
      </div>
      <div ref="trendEl" style="height: 320px" v-loading="trendLoading" />
    </div>

    <!-- 留存 -->
    <div class="am-card">
      <div class="am-toolbar">
        <b>用户留存（按注册日分组）</b>
        <div class="am-spacer" style="flex:1" />
        <el-tag size="small" type="info" effect="plain">次日留存 = D1 列</el-tag>
      </div>
      <div class="am-table-wrap">
        <el-table :data="cohorts" v-loading="retLoading" size="small" stripe>
          <el-table-column prop="date" label="注册日期" width="120" fixed />
          <el-table-column prop="registered" label="注册人数" width="100" />
          <el-table-column v-for="d in retentionDays" :key="d" :label="'D' + d" min-width="86" align="center">
            <template #default="{ row }">
              <span class="ret-cell" :class="retClass(cell(row, d))">
                {{ retText(row, d) }}
              </span>
            </template>
          </el-table-column>
        </el-table>
      </div>
      <el-empty v-if="!retLoading && cohorts.length === 0" description="暂无留存数据（需有用户注册与登录记录）" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref, nextTick } from 'vue'
import * as echarts from 'echarts'
import { statsApi } from '@/api'
import type { Overview, RetentionCohort } from '@/types'

defineOptions({ name: 'DashboardView' })

const ov = ref<Overview>({
  user_total: 0, user_today: 0, user_yesterday: 0, user_week: 0, user_month: 0,
  active_today: 0, active_week: 0, active_month: 0, session_total: 0,
  message_total: 0, order_total: 0, order_paid: 0, income_total: 0
})
const trendDays = ref(30)
const trendLoading = ref(false)
const retLoading = ref(false)
const cohorts = ref<RetentionCohort[]>([])
const retentionDays = ref<number[]>([])

const trendEl = ref<HTMLElement>()
let chart: echarts.ECharts | null = null

const fmt = (n: number | undefined) => (n ?? 0).toLocaleString('zh-CN')

function cell(row: RetentionCohort, d: number): number | null {
  const item = row.retained?.find((r) => r.day === d)
  return item ? item.rate : null
}
function retText(row: RetentionCohort, d: number): string {
  const v = cell(row, d)
  return v == null ? '-' : (v * 100).toFixed(0) + '%'
}
function retClass(v: number | null) {
  if (v == null) return 'ret-low'
  if (v >= 0.5) return 'ret-high'
  if (v >= 0.2) return 'ret-mid'
  return 'ret-low'
}

async function loadOverview() {
  const r = await statsApi.overview()
  ov.value = r.data
}

async function loadTrend() {
  trendLoading.value = true
  try {
    const r = await statsApi.trend(trendDays.value)
    await nextTick()
    renderTrend(r.data.items)
  } finally { trendLoading.value = false }
}

function renderTrend(items: { date: string; registers: number; actives: number }[]) {
  if (!trendEl.value) return
  if (!chart) chart = echarts.init(trendEl.value)
  const dates = items.map((i) => i.date.slice(5))
  chart.setOption({
    color: ['#2563eb', '#f59e0b'],
    tooltip: { trigger: 'axis' },
    legend: { data: ['注册数', '活跃数'], right: 0, top: 0 },
    grid: { left: 12, right: 16, top: 40, bottom: 8, containLabel: true },
    xAxis: { type: 'category', boundaryGap: false, data: dates, axisLine: { lineStyle: { color: '#cbd5e1' } } },
    yAxis: { type: 'value', minInterval: 1, splitLine: { lineStyle: { color: '#eef2f9' } } },
    series: [
      {
        name: '注册数', type: 'line', smooth: true, symbolSize: 5,
        data: items.map((i) => i.registers),
        lineStyle: { width: 3 }, areaStyle: { opacity: 0.12 }
      },
      {
        name: '活跃数', type: 'line', smooth: true, symbolSize: 5,
        data: items.map((i) => i.actives),
        lineStyle: { width: 3 }, areaStyle: { opacity: 0.12 }
      }
    ]
  })
  chart.resize()
}

async function loadRetention() {
  retLoading.value = true
  try {
    const r = await statsApi.retention(7)
    cohorts.value = r.data.cohorts
    retentionDays.value = Array.from({ length: r.data.days }, (_, i) => i)
  } finally { retLoading.value = false }
}

function onResize() { chart?.resize() }

onMounted(async () => {
  await Promise.all([loadOverview(), loadTrend(), loadRetention()])
  window.addEventListener('resize', onResize)
})
onBeforeUnmount(() => {
  window.removeEventListener('resize', onResize)
  chart?.dispose()
  chart = null
})
</script>
