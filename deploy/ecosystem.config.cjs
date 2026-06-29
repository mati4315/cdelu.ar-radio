module.exports = {
  apps: [
    {
      name: 'radio-envivo',
      script: 'src/server.js',
      cwd: '/var/www/radio',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',
      max_restarts: 10,
      restart_delay: 5000,
      exp_backoff_restart_delay: 100,
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      // Log rotation
      error_file: '/var/log/radio/error.log',
      out_file: '/var/log/radio/output.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true
    },
    {
      name: 'radio-loop',
      script: 'loop.sh',
      cwd: '/var/www/radio',
      autorestart: true,
      max_restarts: 5,
      restart_delay: 10000
    },
    {
      name: 'srt-listener',
      script: 'restream.sh',
      cwd: '/var/www/radio',
      autorestart: true,
      max_restarts: 10,
      restart_delay: 5000,
      error_file: '/var/log/radio/srt-error.log',
      out_file: '/var/log/radio/srt-output.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true
    }
  ]
};
