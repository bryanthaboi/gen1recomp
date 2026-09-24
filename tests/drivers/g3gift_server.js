'use strict';

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const net = require('net');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const SERVER_DIR = path.resolve(process.env.POKESERVER_DIR || path.join(__dirname, '..', '..', '..', 'pokeserver'));
const gifts = require(path.join(SERVER_DIR, 'gifts.js'));

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.unref();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => {
      const port = s.address().port;
      s.close(() => resolve(port));
    });
  });
}

function request(port, method, urlPath, body, password) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.from(JSON.stringify(body), 'utf8');
    const headers = {};
    if (data) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = data.length;
    }
    if (password) headers.Authorization = 'Basic ' + Buffer.from('admin:' + password).toString('base64');
    const req = http.request({ host: '127.0.0.1', port, method, path: urlPath, headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ code: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function waitUp(port) {
  for (let i = 0; i < 100; i++) {
    try {
      const r = await request(port, 'GET', gifts.FEED_PATH);
      if (r.code === 200) return r;
    } catch (e) {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  throw new Error('server did not come up');
}

async function main() {
  const dir = fs.mkdtempSync(path.join(process.env.G3GIFT_TMP || os.tmpdir(), 'g3gift-'));
  const keyPath = path.join(dir, 'gift-test.pem');
  const { privateKey } = crypto.generateKeyPairSync('ed25519');
  fs.writeFileSync(keyPath, privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });
  const pub = gifts.publicKeyHex(privateKey);
  const password = crypto.randomBytes(8).toString('hex');
  const httpPort = await freePort();
  const relayPort = await freePort();
  const child = spawn(process.execPath, [path.join(SERVER_DIR, 'server.js')], {
    cwd: SERVER_DIR,
    env: Object.assign({}, process.env, {
      PORT: String(relayPort),
      HTTP_PORT: String(httpPort),
      DASHBOARD_PASSWORD: password,
      GIFT_KEY_PATH: keyPath,
      DATA_DIR: path.join(dir, 'data'),
      CART_MIRROR_ENABLED: '0',
      STATS_ENABLED: '0',
    }),
    stdio: ['ignore', 'ignore', 'inherit'],
  });
  const stop = () => {
    try { child.kill('SIGTERM'); } catch (e) {}
    process.exit(0);
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  child.on('exit', (code) => {
    process.stderr.write('g3gift_server: pokeserver exited ' + code + '\n');
    process.exit(1);
  });

  await waitUp(httpPort);
  const body = [];
  for (let i = 0; i < 10; i++) body.push(['Welcome to the POKéMON', 'WIRELESS CLUB news.', 'New WONDER CARDS arrive', 'over WIRELESS COMMUNICATION.'][i] || '');
  const set = {
    cards: ['mystic_ticket', 'mew', 'stamp_card'].map((key) => ({ key, enabled: true, card: gifts.presetByKey(key).card })),
    news: [{ key: 'club_news', enabled: true, news: { key: 'club_news', id: 1, sendType: 0, bgType: 1, titleText: 'WIRELESS CLUB NEWS', bodyText: body } }],
  };
  const saved = await request(httpPort, 'POST', '/visible/gifts', set, password);
  if (saved.code !== 200) throw new Error('publish failed ' + saved.code + ' ' + saved.body);
  const feed = JSON.parse((await request(httpPort, 'GET', gifts.FEED_PATH)).body);
  if (!gifts.verifyFeed(feed, pub)) throw new Error('feed does not verify under the test key');
  fs.writeFileSync(path.join(dir, 'ready'), httpPort + ' ' + pub + '\n');
  process.stdout.write('READY ' + httpPort + ' ' + pub + ' ' + dir + '\n');
}

main().catch((err) => {
  process.stderr.write('g3gift_server: ' + (err && err.stack || err) + '\n');
  process.exit(1);
});
