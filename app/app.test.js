'use strict';

process.env.NODE_ENV      = 'test';
process.env.POSTGRES_HOST = 'localhost';
process.env.POSTGRES_USER = 'postgres';
process.env.POSTGRES_PASSWORD = 'postgres';
process.env.POSTGRES_DB   = 'testdb';

const request = require('supertest');
const app     = require('../src/app');

beforeAll(() => {
  jest.spyOn(console, 'error').mockImplementation(() => {});
  jest.spyOn(console, 'warn').mockImplementation(() => {});
});

afterAll(async () => {
  jest.restoreAllMocks();
  await new Promise((resolve) => setTimeout(resolve, 500));
});

// ── Health ────────────────────────────────────────────────────────────────────
describe('Health endpoint', () => {
  it('should return 200 with status ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body).toHaveProperty('timestamp');
  });
});

// ── Status ────────────────────────────────────────────────────────────────────
describe('Status endpoint', () => {
  it('should return 200 with checks and metadata', async () => {
    const res = await request(app).get('/status');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('status');
    expect(res.body).toHaveProperty('checks');
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('memoryMB');
  });
});

// ── Process ───────────────────────────────────────────────────────────────────
describe('Process endpoint', () => {
  it('should return 400 when data field is missing', async () => {
    const res = await request(app)
      .post('/process')
      .send({})
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(400);
    expect(res.body).toHaveProperty('error');
  });

  it('should return 400 for empty body', async () => {
    const res = await request(app)
      .post('/process')
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(400);
  });

  it('should return 202 with jobId for valid data', async () => {
    const res = await request(app)
      .post('/process')
      .send({ data: { action: 'test', value: 1 } })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(202);
    expect(res.body).toHaveProperty('jobId');
    expect(res.body.processed).toBe(true);
    expect(res.body).toHaveProperty('processedAt');
  });

  it('should return 202 for string data', async () => {
    const res = await request(app)
      .post('/process')
      .send({ data: 'hello world' })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(202);
    expect(res.body.input).toBe('hello world');
  });
});