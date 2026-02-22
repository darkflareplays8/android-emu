const express = require('express');
const { WebSocketServer } = require('ws');
const { exec, spawn } = require('child_process');
const http = require('http');
const path = require('path');

const app = express();
const server = http.createServer(app);
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── Status ────────────────────────────────────────────────────────────────────
app.get('/api/status', (req, res) => {
  exec('adb devices', (err, stdout) => {
    res.json({
      emulator: stdout && stdout.includes('emulator') ? 'running' : 'starting',
      timestamp: new Date().toISOString()
    });
  });
});

// ── ADB input ─────────────────────────────────────────────────────────────────
app.post('/api/tap',   (req, res) => {
  const { x, y } = req.body;
  exec(`adb -s emulator-5554 shell input tap ${Math.round(x)} ${Math.round(y)}`, () => res.json({ ok: true }));
});

app.post('/api/swipe', (req, res) => {
  const { x1, y1, x2, y2, duration = 200 } = req.body;
  exec(`adb -s emulator-5554 shell input swipe ${x1} ${y1} ${x2} ${y2} ${duration}`, () => res.json({ ok: true }));
});

const SAFE_KEYS = ['KEYCODE_HOME','KEYCODE_BACK','KEYCODE_APP_SWITCH','KEYCODE_ENTER','KEYCODE_DEL','KEYCODE_VOLUME_UP','KEYCODE_VOLUME_DOWN','KEYCODE_POWER'];
app.post('/api/key', (req, res) => {
  const { keycode } = req.body;
  if (!SAFE_KEYS.includes(keycode)) return res.status(403).json({ error: 'Not allowed' });
  exec(`adb -s emulator-5554 shell input keyevent ${keycode}`, () => res.json({ ok: true }));
});

app.post('/api/text', (req, res) => {
  const { text } = req.body;
  exec(`adb -s emulator-5554 shell input text "${text.replace(/"/g, '\\"')}"`, () => res.json({ ok: true }));
});

const ALLOWED_CMDS = ['input','am','pm','settings','wm'];
app.post('/api/adb', (req, res) => {
  const { command } = req.body;
  if (!command) return res.status(400).json({ error: 'No command' });
  if (!ALLOWED_CMDS.includes(command.trim().split(' ')[0])) return res.status(403).json({ error: 'Not allowed' });
  exec(`adb -s emulator-5554 shell ${command}`, { timeout: 5000 }, (err, stdout, stderr) => {
    res.json({ output: stdout, error: stderr || err?.message });
  });
});

app.post('/api/launch', (req, res) => {
  const { pkg } = req.body;
  exec(`adb -s emulator-5554 shell monkey -p ${pkg} -c android.intent.category.LAUNCHER 1`, () => res.json({ ok: true }));
});

// ── H.264 stream via WebSocket ────────────────────────────────────────────────
// Uses scrcpy-server to push raw H.264 NAL units over ADB
// Falls back to screenrecord if scrcpy not available

const wss = new WebSocketServer({ server, path: '/stream' });

wss.on('connection', (ws) => {
  console.log('Stream client connected');

  // Wait for emulator to be ready
  let ready = false;
  const checkReady = setInterval(() => {
    exec('adb -s emulator-5554 shell echo ok', (err, stdout) => {
      if (!err && stdout.includes('ok')) {
        ready = true;
        clearInterval(checkReady);
        startStream(ws);
      }
    });
  }, 2000);

  ws.on('close', () => {
    clearInterval(checkReady);
    if (ws._streamProc) ws._streamProc.kill();
  });
});

function startStream(ws) {
  // Push scrcpy server jar to device, run it, pipe raw H.264 back
  // scrcpy-server produces raw H.264 Annex B — Broadway.js can decode this directly
  const SCRCPY_VERSION = '2.3';

  // First try: use screenrecord --output-format=h264 piped via adb
  // This is the simplest approach — screenrecord on Android 7+ supports h264 output
  const proc = spawn('adb', [
    '-s', 'emulator-5554',
    'shell',
    'screenrecord',
    '--output-format=h264',
    '--size', '540x960',
    '--bit-rate', '2000000',
    '-'   // stdout
  ]);

  ws._streamProc = proc;

  // Buffer to accumulate NAL units and send over WebSocket
  proc.stdout.on('data', (chunk) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(chunk, { binary: true });
    }
  });

  proc.stderr.on('data', (d) => console.error('screenrecord:', d.toString()));

  proc.on('exit', (code) => {
    console.log('screenrecord exited', code);
    // Restart stream after short delay
    if (ws.readyState === ws.OPEN) {
      setTimeout(() => startStream(ws), 1000);
    }
  });
}

server.listen(PORT, () => console.log(`Running on port ${PORT}`));
