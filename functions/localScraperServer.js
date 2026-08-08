const http = require('http');
const { scrapeTalabatMenu } = require('./talabatScraper');

const PORT = Number(process.env.PORT) || 3001;

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  if (req.method === 'GET' && req.url === '/health') {
    sendJson(res, 200, { ok: true, service: 'talabat-scraper' });
    return;
  }

  if (req.method === 'POST' && req.url === '/scrape') {
    try {
      const body = await readBody(req);
      const parsed = JSON.parse(body || '{}');
      const url = String(parsed.url || '').trim();

      if (!url) {
        sendJson(res, 400, { error: 'يرجى إدخال رابط Talabat' });
        return;
      }

      const result = await scrapeTalabatMenu(url);
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 500, {
        error: error.message || 'تعذر سحب المنيو من Talabat',
      });
    }
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Talabat scraper proxy running at http://127.0.0.1:${PORT}`);
});
