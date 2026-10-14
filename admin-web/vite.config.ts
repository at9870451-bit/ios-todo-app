import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

// 管理后台构建：产物输出到 ../quant-java-api/src/main/resources/static/panel
// base 使用绝对路径 /panel/，保证 /panel（无尾斜杠）与 /panel/ 下资源都能正确解析
export default defineConfig({
  base: '/panel/',
  plugins: [vue()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) }
  },
  build: {
    outDir: '../quant-java-api/src/main/resources/static/panel',
    emptyOutDir: true,
    chunkSizeWarningLimit: 2000
  },
  server: {
    port: 5173,
    proxy: {
      '/api': { target: 'http://localhost:8080', changeOrigin: true }
    }
  }
})
