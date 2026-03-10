'use strict';

const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');

const app = express();
app.use(express.json());

// ── Database connections ──────────────────────────────────────────────────────
const getRequiredEnv = (name) => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`CRITICAL: Environment variable ${name} is not set.`);
  }
  return value;
};
// const pgPool = new Pool({
//   host:     process.env.POSTGRES_HOST     || 'postgres',
//   port:     parseInt(process.env.POSTGRES_PORT || '5432'),
//   database: process.env.POSTGRES_DB       || 'appdb',
//   user:     process.env.POSTGRES_USER     || 'appuser',
//   password: process.env.POSTGRES_PASSWORD || 'changeme',
//   max:      10,
//   idleTimeoutMillis: 30000,
//   connectionTimeoutMillis: 2000,
// });

const pgPool = new Pool({
  host:     getRequiredEnv('POSTGRES_HOST'),
  port:     parseInt(process.env.POSTGRES_PORT || '5432'), // Port often has a safe default
  database: getRequiredEnv('POSTGRES_DB'),
  user:     getRequiredEnv('POSTGRES_USER'),
  password: getRequiredEnv('POSTGRES_PASSWORD'),
  max:      10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

const redisClient = redis.createClient({
  url: `redis://${process.env.REDIS_HOST || 'redis'}:${process.env.REDIS_PORT || 6379}`,
});

let redisReady = false;
let pgReady    = false;

redisClient.on('ready',  () => { redisReady = true;  console.log('[redis] connected'); });
redisClient.on('error',  (err) => { redisReady = false; console.error('[redis] error:', err.message); });
redisClient.connect().catch(console.error);

pgPool.on('connect', () => { pgReady = true; console.log('[postgres] client connected'); });
pgPool.on('error',   (err) => { console.error('[postgres] idle client error:', err.message); });

// Warm up postgres connection
pgPool.query('SELECT 1')
  .then(() => { pgReady = true; console.log('[postgres] ready'); })
  .catch((err) => console.error('[postgres] initial connect failed:', err.message));

// ── Routes ────────────────────────────────────────────────────────────────────

/**
 * GET /health
 * Simple liveness probe — always returns 200 if the process is running.
 */
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

/**
 * GET /status
 * Readiness probe — checks downstream dependency health.
 */
app.get('/status', async (_req, res) => {
  const checks = { postgres: false, redis: false };

  // Postgres
  try {
    await pgPool.query('SELECT 1');
    checks.postgres = true;
  } catch (e) {
    console.error('[status] postgres check failed:', e.message);
  }

  // Redis
  try {
    await redisClient.ping();
    checks.redis = true;
  } catch (e) {
    console.error('[status] redis check failed:', e.message);
  }

  const allHealthy = Object.values(checks).every(Boolean);
  res.status(allHealthy ? 200 : 503).json({
    status: allHealthy ? 'ready' : 'degraded',
    checks,
    uptime:   process.uptime(),
    memoryMB: Math.round(process.memoryUsage().rss / 1024 / 1024),
    version:  process.env.APP_VERSION || 'local',
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /process
 * Accepts a JSON body, persists it to Postgres, caches the result in Redis.
 */
app.post('/process', async (req, res) => {
  const { data } = req.body;

  if (!data) {
    return res.status(400).json({ error: '`data` field is required.' });
  }

  const jobId = `job-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const result = { jobId, input: data, processed: true, processedAt: new Date().toISOString() };

  // Persist to Postgres
  try {
    await pgPool.query(
      'INSERT INTO jobs (job_id, input, processed_at) VALUES ($1, $2, $3)',
      [jobId, JSON.stringify(data), result.processedAt],
    );
  } catch (err) {
    console.error('[process] postgres write failed:', err.message);
    return res.status(500).json({ error: 'Database write failed.', detail: err.message });
  }

  // Cache in Redis for 5 minutes
  try {
    await redisClient.setEx(`job:${jobId}`, 300, JSON.stringify(result));
  } catch (err) {
    // Non-fatal: log and continue
    console.warn('[process] redis cache write failed:', err.message);
  }

  return res.status(202).json(result);
});

// ── Graceful shutdown ─────────────────────────────────────────────────────────

async function shutdown(signal) {
  console.log(`[app] received ${signal}, shutting down gracefully...`);
  try {
    await pgPool.end();
    await redisClient.quit();
  } catch (e) {
    console.error('[app] shutdown error:', e.message);
  }
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

// ── Bootstrap ─────────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || '3000');
app.listen(PORT, () => {
  console.log(`[app] listening on port ${PORT} (${process.env.NODE_ENV || 'development'})`);
});

module.exports = app; // for testing
