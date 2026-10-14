// 与后端契约 docs/CONTRACT.md 对应的类型定义

export interface ApiResponse<T = any> {
  code: number
  message: string
  data: T
}

export interface Paged<T> {
  total: number
  page: number
  size: number
  items: T[]
}

export interface AdminInfo {
  id: number
  username: string
  nickname: string
  role_id: number
  role_code: string
  role_name: string
  status: number
  perms: string[]
  last_login_at?: string
  last_login_ip?: string
  created_at?: string
  token?: string
  expires_in?: number
}

export interface UserRow {
  id: number
  username: string
  nickname: string
  email: string
  role: string
  level: string
  status: number
  created_at: string
  last_login_at: string | null
  last_login_ip: string | null
  register_ip: string | null
  live_trading: number
  banned?: boolean
  ban_reason?: string | null
  ban_until?: string | null
}

export interface UserStats {
  sessions: number
  messages: number
  ai_configs: number
  strategies: number
  orders: number
}

export interface LoginLog {
  id: number
  ip: string
  ua: string
  device_model: string
  os_version: string
  app_version: string
  success: number
  created_at: string
}

export interface DeviceInfo {
  id: number
  device_id: string
  device_model: string
  os_version: string
  app_version: string
  last_seen_at: string
  created_at: string
}

export interface ChangeLog {
  id: number
  field: string
  old_value: string
  new_value: string
  operator: string
  source: string
  created_at: string
}

export interface Overview {
  user_total: number
  user_today: number
  user_yesterday: number
  user_week: number
  user_month: number
  active_today: number
  active_week: number
  active_month: number
  session_total: number
  message_total: number
  order_total: number
  order_paid: number
  income_total: number
}

export interface TrendItem { date: string; registers: number; actives: number }
export interface RetentionDay { day: number; count: number; rate: number }
export interface RetentionCohort { date: string; registered: number; retained: RetentionDay[] }

export interface AdminRow {
  id: number
  username: string
  nickname: string
  role_id: number
  role_name: string
  role_code: string
  status: number
  last_login_at: string | null
  last_login_ip: string | null
  created_at: string
}

export interface RoleRow {
  id: number
  name: string
  code: string
  perms: string[]
  remark: string
  admin_count: number
}

export interface OpLog {
  id: number
  admin_id: number
  admin_name: string
  action: string
  method: string
  path: string
  params: string
  ip: string
  status: number
  created_at: string
}

export interface Announcement {
  id: number
  title: string
  content: string
  type: string
  enabled: number
  start_at: string | null
  end_at: string | null
  created_at: string
}

export interface AppVersion {
  id: number
  platform: string
  version: string
  build: number
  force_update: number
  download_url: string
  notes: string
  enabled: number
  created_at: string
}

export type ConfigMap = Record<string, string>

export const LEVELS = [
  { value: 'free', label: '免费版', color: 'info' },
  { value: 'gold', label: '黄金版', color: 'warning' },
  { value: 'diamond', label: '钻石版', color: 'primary' },
  { value: 'ultimate', label: '至尊版', color: 'danger' }
] as const

export const PERM_GROUPS = [
  { name: '用户管理', perms: ['users:read', 'users:ban', 'users:resetpw'] },
  { name: '数据统计', perms: ['stats:read'] },
  { name: 'Doll Studio', perms: ['doll:manage'] },
  { name: '系统管理', perms: ['admins:manage', 'roles:manage', 'logs:read', 'config:manage', 'announcements:manage', 'versions:manage'] }
]

export const PERM_LABELS: Record<string, string> = {
  'users:read': '查看用户',
  'users:ban': '封禁/解封',
  'users:resetpw': '重置用户密码',
  'stats:read': '查看统计',
  'admins:manage': '管理员管理',
  'roles:manage': '角色管理',
  'logs:read': '查看操作日志',
  'config:manage': '系统配置',
  'announcements:manage': '公告管理',
  'versions:manage': '版本管理',
  'doll:manage': 'Doll Studio 管理'
}

// ---------- Doll Studio 3D ----------

export interface DollCategoryRow {
  id: number
  code: string
  name: string
  sort: number
  enabled: boolean
  item_count: number
  created_at: string
}

export interface DollItemRow {
  id: number
  category: string
  name: string
  style: string
  color: string
  premium: boolean
  sort: number
  enabled: boolean
  model_url: string | null
  model_scale: number
  model_offset_y: number
  created_at: string
}

export interface DollOutfitRow {
  id: number
  user_id: number
  username: string
  name: string
  gender: string
  skin: string
  state: string
  favorite: boolean
  created_at: string
  updated_at: string
}

export interface DollAiLogRow {
  id: number
  user_id: number
  username: string
  prompt: string
  status: string
  message: string
  duration_ms: number
  created_at: string
}

export interface DollAiConfigRow {
  id: number
  user_id: number
  username: string
  name: string
  provider_type: string
  api_style: string
  api_url: string
  model: string
  mode: string
  enabled: boolean
  run_count: number
  last_run_at: string | null
  api_key_masked: string
}

export interface DollMeta {
  categories: number
  items: number
  enabled_items: number
  outfits: number
  favorites: number
  ai_calls: number
  ai_errors: number
  styles: Record<string, string[]>
}
