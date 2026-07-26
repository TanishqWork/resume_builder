// PM2 process definition for the FastAPI backend.
//
// PM2 normally runs Node, but it happily supervises any executable — here it
// runs uvicorn straight out of the project's virtualenv. That keeps this app
// consistent with how quiz-backend / next-app are managed on this box.
//
//   pm2 start  /var/www/resume/deploy/ecosystem.config.cjs
//   pm2 reload resume-backend      # zero-downtime redeploy
//   pm2 logs   resume-backend
//   pm2 save                       # persist across reboot
//
// .cjs (not .js) because the repo has no package.json at the root and PM2
// expects CommonJS here.

const APP_ROOT = '/var/www/resume/backend'

module.exports = {
  apps: [
    {
      name: 'resume-backend',

      // The venv's uvicorn — no `source activate` needed, the shebang inside
      // this binary already points at venv/bin/python3.12.
      script: `${APP_ROOT}/venv/bin/uvicorn`,
      interpreter: 'none',

      // Bound to loopback ONLY. Nginx is the sole public entrance; port 8100
      // is never reachable from the internet.
      //
      // --proxy-headers + --forwarded-allow-ips lets uvicorn trust the
      // X-Forwarded-* headers that nginx sets, so request.url.scheme is
      // https and the demo IP gate sees the real client address.
      args: [
        'app.main:app',
        '--host', '127.0.0.1',
        '--port', '8100',
        '--proxy-headers',
        '--forwarded-allow-ips', '127.0.0.1',
      ].join(' '),

      cwd: APP_ROOT,

      // fork mode, 1 instance. pdflatex is CPU-bound and this is a 2 vCPU box,
      // so a second worker would fight the first for cores. If /generate starts
      // queueing under real traffic, bump to 2 and re-measure:
      //   instances: 2, exec_mode: 'cluster'   <-- see deploy/README.md caveat
      instances: 1,
      exec_mode: 'fork',

      // config.py reads .env from cwd; PM2 also injects these.
      env: {
        PYTHONUNBUFFERED: '1',      // logs appear immediately, not on flush
        PYTHONDONTWRITEBYTECODE: '1',
      },

      // Restart policy. A crash-looping process backs off instead of hammering.
      autorestart: true,
      max_restarts: 10,
      min_uptime: '20s',
      restart_delay: 2000,

      // A LaTeX-heavy process can creep; recycle if it balloons.
      max_memory_restart: '1G',

      error_file: '/var/log/resume/backend-error.log',
      out_file: '/var/log/resume/backend-out.log',
      merge_logs: true,
      time: true,        // timestamp every log line
    },
  ],
}
