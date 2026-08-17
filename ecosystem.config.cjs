/** PM2 process file for the three Node runtimes (backend, worker, telegram-bot).
 *  Used by `.github/workflows/ci-cd.yml` on the self-hosted Mac Mini.
 *  Each app loads its own `.env.production` from `cwd` via dotenv.
 *  Keep worker + telegram-bot at 1 instance — BullMQ cron and grammy polling
 *  are not safe to cluster.
 */
module.exports = {
  apps: [
    {
      name: 'ptas168-api',
      cwd: './apps/backend',
      script: 'dist/server.js',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '500M',
      env_production: {
        NODE_ENV: 'production',
        PORT: 3001,
      },
      error_file: './logs/err.log',
      out_file: './logs/out.log',
      merge_logs: true,
      time: true,
    },
    {
      name: 'ptas168-worker',
      cwd: './apps/worker',
      script: 'dist/index.js',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '300M',
      env_production: {
        NODE_ENV: 'production',
      },
      error_file: './logs/err.log',
      out_file: './logs/out.log',
      merge_logs: true,
      time: true,
    },
    {
      name: 'ptas168-telegram-bot',
      cwd: './apps/telegram-bot',
      script: 'dist/index.js',
      instances: 1,
      exec_mode: 'fork',
      max_memory_restart: '300M',
      env_production: {
        NODE_ENV: 'production',
      },
      error_file: './logs/err.log',
      out_file: './logs/out.log',
      merge_logs: true,
      time: true,
    },
  ],
}
