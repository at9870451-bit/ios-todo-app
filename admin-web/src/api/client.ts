import axios, { type AxiosInstance } from 'axios'
import { ElMessage } from 'element-plus'

// 管理后台 API 基址：同源部署（jar 内 /panel）时用相对路径；
// 独立开发时通过 vite proxy 转发到 8080。
const BASE = '/api/console'

export const TOKEN_KEY = 'amore_console_token'
export const ADMIN_KEY = 'amore_console_admin'

const http: AxiosInstance = axios.create({ baseURL: BASE, timeout: 20000 })

http.interceptors.request.use((cfg) => {
  const token = localStorage.getItem(TOKEN_KEY)
  if (token) cfg.headers.Authorization = `Bearer ${token}`
  return cfg
})

http.interceptors.response.use(
  (resp) => {
    const body = resp.data
    if (body && typeof body === 'object' && 'code' in body && body.code !== 0) {
      ElMessage.error(body.message || '请求失败')
      return Promise.reject(new Error(body.message || '请求失败'))
    }
    return body
  },
  (err) => {
    const status = err?.response?.status
    const msg = err?.response?.data?.message || err.message || '网络错误'
    if (status === 401 || err?.response?.data?.code === 401) {
      localStorage.removeItem(TOKEN_KEY)
      localStorage.removeItem(ADMIN_KEY)
      if (!location.hash.includes('/login')) location.hash = '#/login'
      ElMessage.error('登录已过期，请重新登录')
    } else {
      ElMessage.error(msg)
    }
    return Promise.reject(err)
  }
)

export default http
