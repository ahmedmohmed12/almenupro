'use strict';

const http = require('node:http');

const MAX_BODY_BYTES = 1024 * 1024;

function sendJson(response, status, body) {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  response.end(JSON.stringify(body));
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      const error = new Error('Mock payload is too large');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  } catch {
    const error = new Error('Mock payload must be valid JSON');
    error.statusCode = 400;
    throw error;
  }
}

class MockOrderServer {
  constructor({ port, secret, ingestor, onError = () => {} }) {
    this.port = port;
    this.secret = secret;
    this.ingestor = ingestor;
    this.onError = onError;
    this.server = null;
  }

  async start() {
    if (this.server) return;
    this.server = http.createServer((request, response) => {
      this.handle(request, response).catch((error) => {
        this.safeError(error);
        if (!response.headersSent) {
          sendJson(response, error.statusCode || 500, {
            ok: false,
            error: String(error.message || error),
          });
        } else if (!response.writableEnded) {
          response.end();
        }
      });
    });
    this.server.on('clientError', (error, socket) => {
      this.safeError(error);
      if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    });
    await new Promise((resolve, reject) => {
      this.server.once('error', reject);
      this.server.listen(this.port, '127.0.0.1', resolve);
    });
  }

  async handle(request, response) {
    if (request.method !== 'POST' || request.url !== '/inject') {
      sendJson(response, 404, { ok: false, error: 'Not found' });
      return;
    }
    const token = String(request.headers.authorization || '').replace(
      /^Bearer\s+/i,
      '',
    );
    if (!token || token !== this.secret) {
      sendJson(response, 401, { ok: false, error: 'Unauthorized' });
      return;
    }
    const body = await readJson(request);
    const provider = String(body.platform || body.provider || '').toLowerCase();
    const orders = Array.isArray(body.orders) ? body.orders : [body];
    const result = this.ingestor.ingest(provider, orders, { source: 'mock-cli' });
    sendJson(response, result.rejected ? 422 : 202, {
      ok: result.rejected === 0,
      ...result,
    });
  }

  async stop() {
    if (!this.server) return;
    const server = this.server;
    this.server = null;
    await new Promise((resolve) => server.close(resolve));
  }

  safeError(error) {
    try {
      this.onError(error);
    } catch (callbackError) {
      console.error('Mock server error callback failed:', callbackError);
    }
  }
}

module.exports = { MockOrderServer, readJson };
