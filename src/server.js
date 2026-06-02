'use strict';

const path = require('node:path');
const { exec } = require('node:child_process');
const util = require('node:util');
const { existsSync } = require('node:fs');
const Fastify = require('fastify');
const fastifyStatic = require('@fastify/static');
const dotenv = require('dotenv');

// Cargar .env solo si existe (produccion o desarrollo local)
const envPath = path.join(__dirname, '..', '.env');
if (existsSync(envPath)) {
  dotenv.config({ path: envPath });
}

const execAsync = util.promisify(exec);

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const SOURCE_USER = process.env.SOURCE_USER || '';
const SOURCE_PASS = process.env.SOURCE_PASS || '';
const STREAM_NAME = process.env.STREAM_NAME || 'Radio Live';
const OFFLINE_TIMEOUT_MS = Number(process.env.OFFLINE_TIMEOUT_MS || 12000);
const MAX_BUFFER_MB = Number(process.env.MAX_BUFFER_MB || 50);
const BUFFER_CHUNKS = Math.max(1, Number(process.env.BUFFER_CHUNKS || 64));

const serverFactory = (handler, opts) => {
  const server = require('node:http').createServer((req, res) => {
    // Icecast clients like BUTT use the custom 'SOURCE' method.
    // Fastify natively rejects it, so we remap it to 'PUT' before it reaches Fastify.
    if (req.method === 'SOURCE') {
      req.method = 'PUT';
    }
    handler(req, res);
  });
  return server;
};

const app = Fastify({ serverFactory, logger: true, bodyLimit: 1073741824 });
// Solo parseamos JSON explicitamente para los endpoints de admin
app.addContentTypeParser('application/json', { parseAs: 'buffer' }, (req, body, done) => {
  try {
    done(null, JSON.parse(body.toString()));
  } catch (e) {
    done(null, body.toString());
  }
});
// Para todo lo demas, devolvemos el payload (stream) sin consumir
// para que el endpoint /source pueda hacer request.raw.on('data', ...)
app.addContentTypeParser('*', function (request, payload, done) {
  done(null, payload);
});

// Favion para evitar 404 repetido
app.get('/favicon.ico', async (request, reply) => {
  return reply.code(204).send();
});

const listeners = new Set();
const recentChunks = [];
let approximateBufferBytes = 0;

let sourceReq = null;
let sourceConnectedAt = null;
let lastSeen = null;
let totalBytesIn = 0;

function pushChunk(chunk) {
  if (!chunk || chunk.length === 0) {
    return;
  }
  const MAX_BUFFER_BYTES = MAX_BUFFER_MB * 1024 * 1024;
  recentChunks.push(chunk);
  approximateBufferBytes += chunk.length;
  while (recentChunks.length > BUFFER_CHUNKS && approximateBufferBytes > MAX_BUFFER_BYTES) {
    const old = recentChunks.shift();
    if (old) {
      approximateBufferBytes -= old.length;
    }
  }
  // Si el buffer en bytes explota, recortar por cantidad tambien
  if (recentChunks.length > BUFFER_CHUNKS * 2) {
    const old = recentChunks.shift();
    if (old) approximateBufferBytes -= old.length;
  }
}

function writeToListeners(chunk) {
  for (const reply of listeners) {
    try {
      reply.raw.write(chunk);
    } catch (err) {
      app.log.warn({ err }, 'listener write failed');
      listeners.delete(reply);
      safeEnd(reply.raw);
    }
  }
}

function safeEnd(res) {
  try {
    if (!res.writableEnded) {
      res.end();
    }
  } catch (_) {
    // Ignore close errors.
  }
}

function isLive() {
  if (!sourceReq) {
    return false;
  }
  if (!lastSeen) {
    return false;
  }
  // Allow the connection to sit idle for up to 12 hours before the first byte arrives.
  // This is crucial for the ffmpeg | curl pipeline, which connects curl immediately
  // even while ffmpeg is waiting for an incoming SRT connection.
  if (totalBytesIn === 0) {
    return Date.now() - lastSeen <= 12 * 3600 * 1000;
  }
  return Date.now() - lastSeen <= OFFLINE_TIMEOUT_MS;
}

setInterval(() => {
  if (!isLive() && sourceReq) {
    app.log.warn('source heartbeat timeout; forcing source disconnect');
    try {
      sourceReq.destroy();
    } catch (_) {
      // Ignore destroy errors.
    }
  }
}, Math.max(2000, Math.floor(OFFLINE_TIMEOUT_MS / 2))).unref();

app.register(fastifyStatic, {
  root: path.join(__dirname, '..', 'public'),
  prefix: '/'
});

app.addHook('onRequest', async (request, reply) => {
  const isSourceEndpoint = request.url === '/source' && (request.method === 'POST' || request.method === 'PUT');
  const isAdminEndpoint = request.url.startsWith('/api/autodj') || request.url.startsWith('/api/srt');

  if (isSourceEndpoint || isAdminEndpoint) {
    const auth = request.headers.authorization || '';
    const expected = `Basic ${Buffer.from(`${SOURCE_USER}:${SOURCE_PASS}`).toString('base64')}`;

    if (!SOURCE_USER || !SOURCE_PASS) {
      request.log.error('SOURCE_USER/SOURCE_PASS not configured');
      return reply.code(500).send({ error: 'Server not configured for source auth' });
    }

    if (auth !== expected) {
      reply.header('WWW-Authenticate', 'Basic realm="radio-admin"');
      return reply.code(401).send({ error: 'Unauthorized' });
    }
  }
});

app.route({
  method: ['POST', 'PUT'],
  url: '/source',
  handler: async (request, reply) => {
    if (sourceReq && sourceReq !== request.raw) {
      request.log.warn('existing source replaced by a new one');
      try {
        sourceReq.destroy();
      } catch (_) {
        // Ignore
      }
    }

    const rawReq = request.raw;
    sourceReq = rawReq;
    sourceConnectedAt = new Date().toISOString();
    lastSeen = Date.now();
    totalBytesIn = 0;
    recentChunks.length = 0;
    approximateBufferBytes = 0;

    request.log.info({ ip: request.ip, sourceConnectedAt }, 'source connected');

    // Determine the data stream to read from.
    // Fastify's content type parser may have already consumed request.raw,
    // so we check if the body is a readable stream (e.g. from BUTT/Icecast).
    // For curl with chunked transfer, request.raw is still readable.
    const body = request.body;
    const isBodyStream = body && typeof body.on === 'function' && typeof body.read === 'function';
    const dataStream = isBodyStream ? body : rawReq;

    request.log.info({ usingBodyStream: isBodyStream }, 'source data stream selected');

    dataStream.on('data', (chunk) => {
      lastSeen = Date.now();
      totalBytesIn += chunk.length;
      pushChunk(chunk);
      writeToListeners(chunk);
    });

    dataStream.on('end', () => {
      request.log.warn('source disconnected (end)');
      if (sourceReq === rawReq) {
        sourceReq = null;
        sourceConnectedAt = null;
      }
    });

    rawReq.on('close', () => {
      request.log.warn({ stillSource: sourceReq === rawReq }, 'source disconnected (close)');
      if (sourceReq === rawReq) {
        sourceReq = null;
        sourceConnectedAt = null;
      }
    });

    dataStream.on('error', (err) => {
      request.log.error({ err }, 'source stream error');
      if (sourceReq === rawReq) {
        sourceReq = null;
        sourceConnectedAt = null;
      }
    });

    // Resume the data stream in case it is paused (common with Fastify body streams)
    if (isBodyStream && typeof dataStream.resume === 'function') {
      dataStream.resume();
    }

    reply.raw.writeHead(200, {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store'
    });
    reply.raw.write('SOURCE_OK\n');

    await new Promise((resolve) => {
      rawReq.once('close', resolve);
      dataStream.once('end', resolve);
      dataStream.once('error', resolve);
    });

    safeEnd(reply.raw);
    return reply;
  }
});

app.get('/En-vivo-Cdelu.mp3', async (request, reply) => {
  return serveLiveStream(request, reply);
});

app.get('/live.mp3', async (request, reply) => {
  return serveLiveStream(request, reply);
});

async function serveLiveStream(request, reply) {
  reply.raw.writeHead(200, {
    'Content-Type': 'audio/mpeg',
    'Cache-Control': 'no-cache, no-store, must-revalidate, private',
    Pragma: 'no-cache',
    Expires: '0',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
    'Transfer-Encoding': 'chunked'
  });

  for (const chunk of recentChunks) {
    reply.raw.write(chunk);
  }

  listeners.add(reply);
  request.log.info({ listeners: listeners.size, ip: request.ip }, 'listener connected');

  const cleanup = () => {
    listeners.delete(reply);
    safeEnd(reply.raw);
    request.log.info({ listeners: listeners.size }, 'listener disconnected');
  };

  request.raw.once('close', cleanup);
  request.raw.once('error', cleanup);

  return reply;
}

app.get('/status', async () => {
  return {
    streamName: STREAM_NAME,
    live: isLive(),
    listeners: listeners.size,
    sourceConnectedAt,
    sourceReqExists: sourceReq !== null,
    lastSeen: lastSeen ? new Date(lastSeen).toISOString() : null,
    totalBytesIn
  };
});

app.get('/api/autodj/status', async (request, reply) => {
  try {
    const { stdout } = await execAsync('pm2 jlist');
    const list = JSON.parse(stdout);
    const loopProcess = list.find(p => p.name === 'radio-loop');
    const isRunning = loopProcess && loopProcess.pm2_env.status === 'online';
    return { isRunning };
  } catch (err) {
    request.log.error(err);
    return reply.code(500).send({ error: 'Failed to get pm2 status' });
  }
});

app.post('/api/autodj', async (request, reply) => {
  let body = request.body;
  // Si el body es un stream (porque no se parseo como JSON), lo consumimos
  if (body && typeof body.on === 'function') {
    body = await new Promise((resolve) => {
      const chunks = [];
      body.on('data', (c) => chunks.push(c));
      body.on('end', () => resolve(Buffer.concat(chunks).toString()));
    });
  }
  const raw = body || {};
  let action = typeof raw === 'object' ? raw.action : null;
  // Parse manual si es string
  if (typeof raw === 'string') {
    try { action = JSON.parse(raw).action; } catch(e) {}
  } else if (Buffer.isBuffer(raw)) {
    try { action = JSON.parse(raw.toString()).action; } catch(e) {}
  }

  try {
    if (action === 'start') {
      await execAsync('pm2 start radio-loop');
    } else if (action === 'stop') {
      await execAsync('pm2 stop radio-loop');
      // Asegurarse de que los procesos hijos mueran
      try { await execAsync('pkill -f "ffmpeg -re -i"'); } catch(e) {}
      try { await execAsync('pkill -f "curl.*source"'); } catch(e) {}
    } else {
      return reply.code(400).send({ error: 'Invalid action' });
    }
    return { success: true };
  } catch (err) {
    request.log.error(err);
    return reply.code(500).send({ error: 'Command failed' });
  }
});

app.get('/api/srt/status', async (request, reply) => {
  try {
    const { stdout } = await execAsync('pm2 jlist');
    const list = JSON.parse(stdout);
    const srtProcess = list.find(p => p.name === 'srt-listener');
    const isRunning = srtProcess && srtProcess.pm2_env.status === 'online';
    return { isRunning };
  } catch (err) {
    request.log.error(err);
    return reply.code(500).send({ error: 'Failed to get pm2 status' });
  }
});

app.post('/api/srt', async (request, reply) => {
  let body = request.body;
  if (body && typeof body.on === 'function') {
    body = await new Promise((resolve) => {
      const chunks = [];
      body.on('data', (c) => chunks.push(c));
      body.on('end', () => resolve(Buffer.concat(chunks).toString()));
    });
  }
  const raw = body || {};
  let action = typeof raw === 'object' ? raw.action : null;
  if (typeof raw === 'string') {
    try { action = JSON.parse(raw).action; } catch(e) {}
  } else if (Buffer.isBuffer(raw)) {
    try { action = JSON.parse(raw.toString()).action; } catch(e) {}
  }

  try {
    if (action === 'start') {
      await execAsync('pm2 start srt-listener');
    } else if (action === 'stop') {
      await execAsync('pm2 stop srt-listener');
      try { await execAsync('pkill -f "ffmpeg.*srt"'); } catch(e) {}
    } else {
      return reply.code(400).send({ error: 'Invalid action' });
    }
    return { success: true };
  } catch (err) {
    request.log.error(err);
    return reply.code(500).send({ error: 'Command failed' });
  }
});

app.get('/healthz', async () => ({ ok: true }));

// ── Recordings API ──────────────────────────────────────────────────────────
const fs = require('node:fs');
const RECORDINGS_DIR = path.join(__dirname, '..', 'public', 'recordings');

app.get('/api/recordings', async (request, reply) => {
  try {
    if (!fs.existsSync(RECORDINGS_DIR)) {
      return { recordings: [] };
    }
    const files = fs.readdirSync(RECORDINGS_DIR)
      .filter(f => f.endsWith('.mp4'))
      .map(f => {
        const stat = fs.statSync(path.join(RECORDINGS_DIR, f));
        return {
          filename: f,
          url: `/recordings/${f}`,
          sizeMB: (stat.size / 1024 / 1024).toFixed(2),
          date: stat.mtime.toISOString()
        };
      })
      .sort((a, b) => new Date(b.date) - new Date(a.date));
    return { recordings: files };
  } catch (err) {
    request.log.error(err);
    return reply.code(500).send({ error: 'Failed to list recordings' });
  }
});


// Graceful shutdown
const gracefulShutdown = async (signal) => {
  app.log.info({ signal }, 'received shutdown signal');
  for (const reply of listeners) {
    try { safeEnd(reply.raw); } catch (_) {}
  }
  listeners.clear();
  await app.close();
  process.exit(0);
};
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

app.listen({ port: PORT, host: HOST })
  .then(() => {
    app.log.info({ PORT, HOST }, 'radio relay server started');
  })
  .catch((err) => {
    app.log.error({ err }, 'failed to start server');
    process.exit(1);
  });
