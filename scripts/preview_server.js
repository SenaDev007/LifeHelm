/**
 * Serveur preview LifeHelm — sert le build web Flutter ET proxifie /api/*
 * vers le backend NestJS (port 3001) en same-origin :
 *   - l'app appelle /api/v1/... en chemin relatif (défaut)
 *   - la preview publique (proxy :81 → 3000) expose donc l'app ET l'API
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_ROOT = process.argv[2] || '/home/z/my-project/lifehelm/build/web';
const PORT = Number(process.argv[3] || 3000);
const API_PORT = Number(process.env.API_PORT || 3001);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

function proxyToApi(req, res) {
  const options = {
    hostname: '127.0.0.1',
    port: API_PORT,
    path: req.url,
    method: req.method,
    headers: { ...req.headers, host: `127.0.0.1:${API_PORT}` },
  };
  const upstream = http.request(options, (upRes) => {
    res.writeHead(upRes.statusCode ?? 502, upRes.headers);
    upRes.pipe(res);
  });
  upstream.on('error', (err) => {
    res.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ statusCode: 502, code: 'BAD_GATEWAY', message: 'API injoignable : ' + err.message }));
  });
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  // API → proxy vers NestJS
  if (req.url && (req.url.startsWith('/api/') || req.url === '/api')) {
    proxyToApi(req, res);
    return;
  }

  // Fichiers statiques
  let urlPath = decodeURIComponent((req.url ?? '/').split('?')[0]);
  let filePath = path.normalize(path.join(WEB_ROOT, urlPath));
  if (!filePath.startsWith(WEB_ROOT)) {
    res.writeHead(403);
    res.end('Interdit');
    return;
  }
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    // SPA : toute route inconnue → index.html
    filePath = path.join(WEB_ROOT, 'index.html');
  }
  const ext = path.extname(filePath).toLowerCase();
  const mime = MIME[ext] ?? 'application/octet-stream';
  const cacheable = filePath.includes('/assets/') || ext === '.wasm' || ext === '.js' || ext === '.otf' || ext === '.ttf';
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Introuvable');
      return;
    }
    res.writeHead(200, {
      'Content-Type': mime,
      'Cache-Control': cacheable ? 'public, max-age=3600' : 'no-cache',
    });
    res.end(data);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Preview LifeHelm : http://0.0.0.0:${PORT}  (statique ${WEB_ROOT} + proxy /api → :${API_PORT})`);
});
