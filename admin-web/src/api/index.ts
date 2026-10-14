import http from './client'
import type {
  ApiResponse, Paged, AdminInfo, UserRow, UserStats, LoginLog, DeviceInfo, ChangeLog,
  Overview, TrendItem, RetentionCohort, AdminRow, RoleRow, OpLog, Announcement, AppVersion, ConfigMap,
  DollCategoryRow, DollItemRow, DollOutfitRow, DollAiLogRow, DollAiConfigRow, DollMeta
} from '@/types'

// ---------- 认证 ----------
export const authApi = {
  login: (username: string, password: string) =>
    http.post<any, ApiResponse<AdminInfo>>('/auth/login', { username, password }),
  me: () => http.get<any, ApiResponse<AdminInfo>>('/auth/me'),
  logout: () => http.post<any, ApiResponse<null>>('/auth/logout'),
  password: (old_password: string, new_password: string) =>
    http.post<any, ApiResponse<null>>('/auth/password', { old_password, new_password })
}

// ---------- 用户 ----------
export interface UserQuery {
  page?: number; size?: number; keyword?: string; status?: string; level?: string
  date_from?: string; date_to?: string; order?: string; dir?: string
}

export const userApi = {
  list: (q: UserQuery) => http.get<any, ApiResponse<Paged<UserRow>>>('/users', { params: q }),
  detail: (id: number) => http.get<any, ApiResponse<{ user: UserRow; stats: UserStats }>>(`/users/${id}`),
  logins: (id: number, page = 1, size = 20) =>
    http.get<any, ApiResponse<Paged<LoginLog>>>(`/users/${id}/logins`, { params: { page, size } }),
  devices: (id: number) => http.get<any, ApiResponse<{ items: DeviceInfo[] }>>(`/users/${id}/devices`),
  changes: (id: number, page = 1, size = 20) =>
    http.get<any, ApiResponse<Paged<ChangeLog>>>(`/users/${id}/changes`, { params: { page, size } }),
  ban: (id: number, reason: string, days: number) => http.post<any, ApiResponse<null>>(`/users/${id}/ban`, { reason, days }),
  unban: (id: number) => http.post<any, ApiResponse<null>>(`/users/${id}/unban`),
  resetPassword: (id: number, new_password: string) =>
    http.post<any, ApiResponse<null>>(`/users/${id}/reset-password`, { new_password })
}

// ---------- 统计 ----------
export const statsApi = {
  overview: () => http.get<any, ApiResponse<Overview>>('/stats/overview'),
  trend: (days = 30) => http.get<any, ApiResponse<{ days: number; items: TrendItem[] }>>('/stats/trend', { params: { days } }),
  retention: (days = 7) => http.get<any, ApiResponse<{ days: number; cohorts: RetentionCohort[] }>>('/stats/retention', { params: { days } })
}

// ---------- 管理员 / 角色 ----------
export const adminApi = {
  list: () => http.get<any, ApiResponse<{ items: AdminRow[] }>>('/admins'),
  create: (payload: { username: string; nickname: string; password: string; role_id: number }) =>
    http.post<any, ApiResponse<{ id: number }>>('/admins', payload),
  update: (id: number, payload: { nickname?: string; role_id?: number; status?: number }) =>
    http.put<any, ApiResponse<null>>(`/admins/${id}`, payload),
  resetPassword: (id: number, new_password: string) =>
    http.post<any, ApiResponse<null>>(`/admins/${id}/reset-password`, { new_password }),
  remove: (id: number) => http.delete<any, ApiResponse<null>>(`/admins/${id}`)
}

export const roleApi = {
  list: () => http.get<any, ApiResponse<{ items: RoleRow[] }>>('/roles'),
  create: (payload: { name: string; code: string; perms: string[]; remark: string }) =>
    http.post<any, ApiResponse<{ id: number }>>('/roles', payload),
  update: (id: number, payload: { name?: string; perms?: string[]; remark?: string }) =>
    http.put<any, ApiResponse<null>>(`/roles/${id}`, payload),
  remove: (id: number) => http.delete<any, ApiResponse<null>>(`/roles/${id}`)
}

// ---------- 操作日志 ----------
export const logApi = {
  list: (params: { page?: number; size?: number; keyword?: string; admin_id?: number; date_from?: string; date_to?: string }) =>
    http.get<any, ApiResponse<Paged<OpLog>>>('/logs', { params })
}

// ---------- 系统配置 ----------
export const configApi = {
  get: () => http.get<any, ApiResponse<ConfigMap>>('/config'),
  save: (payload: ConfigMap) => http.put<any, ApiResponse<null>>('/config', payload)
}

export const announcementApi = {
  list: () => http.get<any, ApiResponse<{ items: Announcement[] }>>('/announcements'),
  create: (payload: Partial<Announcement>) => http.post<any, ApiResponse<{ id: number }>>('/announcements', payload),
  update: (id: number, payload: Partial<Announcement>) => http.put<any, ApiResponse<null>>(`/announcements/${id}`, payload),
  remove: (id: number) => http.delete<any, ApiResponse<null>>(`/announcements/${id}`)
}

export const versionApi = {
  list: () => http.get<any, ApiResponse<{ items: AppVersion[] }>>('/versions'),
  create: (payload: Partial<AppVersion>) => http.post<any, ApiResponse<{ id: number }>>('/versions', payload),
  update: (id: number, payload: Partial<AppVersion>) => http.put<any, ApiResponse<null>>(`/versions/${id}`, payload),
  remove: (id: number) => http.delete<any, ApiResponse<null>>(`/versions/${id}`)
}

// ---------- Doll Studio 3D ----------

export const dollApi = {
  meta: () => http.get<any, ApiResponse<DollMeta>>('/doll/meta'),
  categories: () => http.get<any, ApiResponse<{ items: DollCategoryRow[] }>>('/doll/categories'),
  updateCategory: (id: number, payload: { name?: string; sort?: number; enabled?: boolean }) =>
    http.put<any, ApiResponse<null>>(`/doll/categories/${id}`, payload),
  items: (params: { page?: number; size?: number; category?: string; keyword?: string }) =>
    http.get<any, ApiResponse<Paged<DollItemRow>>>('/doll/items', { params }),
  createItem: (payload: Partial<DollItemRow>) => http.post<any, ApiResponse<{ id: number }>>('/doll/items', payload),
  updateItem: (id: number, payload: Partial<DollItemRow>) => http.put<any, ApiResponse<null>>(`/doll/items/${id}`, payload),
  removeItem: (id: number) => http.delete<any, ApiResponse<null>>(`/doll/items/${id}`),
  uploadModel: (file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    return http.post<any, ApiResponse<{ url: string; name: string; size: number }>>('/doll/upload', fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
      timeout: 120000
    })
  },
  outfits: (params: { page?: number; size?: number; keyword?: string }) =>
    http.get<any, ApiResponse<Paged<DollOutfitRow>>>('/doll/outfits', { params }),
  removeOutfit: (id: number) => http.delete<any, ApiResponse<null>>(`/doll/outfits/${id}`),
  aiLogs: (params: { page?: number; size?: number; status?: string }) =>
    http.get<any, ApiResponse<Paged<DollAiLogRow>>>('/doll/ai-logs', { params }),
  aiLogDetail: (id: number) => http.get<any, ApiResponse<DollAiLogRow & { result: string }>>(`/doll/ai-logs/${id}`),
  aiConfigs: (params: { page?: number; size?: number }) =>
    http.get<any, ApiResponse<Paged<DollAiConfigRow>>>('/doll/ai-configs', { params })
}
