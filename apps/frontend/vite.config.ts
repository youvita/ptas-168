import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const backendUrl = env.BACKEND_URL ?? 'http://localhost:3001'

  return {
    plugins: [react()],
    server: {
      port: 8080,
      host: true,
      strictPort: true,
      proxy: {
        // /api/* → ptas168-api (backend listens on :3001; override via BACKEND_URL in .env.local)
        '/api': {
          target: backendUrl,
          changeOrigin: true,
        },
      },
    },
    // Shared Mini Mac edge uses /ptas168 so one Cloudflare URL can serve
    // we-testcase + SecureScan + PTAS168. Local/dev keeps `/`.
    base: env.VITE_BASE_PATH || process.env.VITE_BASE_PATH || '/',
  }
})
