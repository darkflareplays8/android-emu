const express = require('express');
const { exec, spawn } = require('child_process');
const http = require('http');
const path = require('path');
const fs = require('fs');

const app = express();
const server = http.createServer(app);

const PORT = process.env.PORT || 3000;
const VNC_WS_PORT = 6080;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── Status endpoint ──────────────────────────────────────────────────────────
app.get('/api/status', (req, res) => {
  exec('adb devices', (err, stdout) => {
    const connected = stdout && stdout.includes('emulator');
    res.json({
      emulator: connected ? 'running' : 'starting',
      vnc_port: VNC_WS_PORT,
      timestamp: new Date().toISOString()
    });
  });
});

// ── ADB shell command (safe subset) ─────────────────────────────────────────
const ALLOWED_COMMANDS = ['input', 'am', 'pm', 'settings', 'wm'];

app.post('/api/adb', (req, res) => {
  const { command } = req.body;
  if (!command) return res.status(400).json({ error: 'No command provided' });

  const parts = command.trim().split(' ');
  if (!ALLOWED_COMMANDS.includes(parts[0])) {
    return res.status(403).json({ error: 'Command not allowed' });
  }

  exec(`adb -s emulator-5554 shell ${command}`, { timeout: 5000 }, (err, stdout, stderr) => {
    res.json({ output: stdout, error: stderr || err?.message });
  });
});

// ── Tap shortcut ─────────────────────────────────────────────────────────────
app.post('/api/tap', (req, res) => {
  const { x, y } = req.body;
  if (x == null || y == null) return res.status(400).json({ error: 'x and y required' });
  exec(`adb -s emulator-5554 shell input tap ${Math.round(x)} ${Math.round(y)}`, (err, stdout) => {
    res.json({ ok: !err, error: err?.message });
  });
});

// ── Swipe shortcut ───────────────────────────────────────────────────────────
app.post('/api/swipe', (req, res) => {
  const { x1, y1, x2, y2, duration = 300 } = req.body;
  exec(`adb -s emulator-5554 shell input swipe ${x1} ${y1} ${x2} ${y2} ${duration}`, (err) => {
    res.json({ ok: !err, error: err?.message });
  });
});

// ── Key event ────────────────────────────────────────────────────────────────
app.post('/api/key', (req, res) => {
  const { keycode } = req.body;
  const SAFE_KEYS = ['KEYCODE_HOME', 'KEYCODE_BACK', 'KEYCODE_APP_SWITCH',
                     'KEYCODE_VOLUME_UP', 'KEYCODE_VOLUME_DOWN', 'KEYCODE_POWER',
                     'KEYCODE_ENTER', 'KEYCODE_DEL'];
  if (!SAFE_KEYS.includes(keycode)) return res.status(403).json({ error: 'Key not allowed' });
  exec(`adb -s emulator-5554 shell input keyevent ${keycode}`, (err) => {
    res.json({ ok: !err, error: err?.message });
  });
});

// ── Screenshot ───────────────────────────────────────────────────────────────
app.get('/api/screenshot', (req, res) => {
  exec('adb -s emulator-5554 exec-out screencap -p', { encoding: 'buffer', timeout: 8000 }, (err, stdout) => {
    if (err) return res.status(500).json({ error: 'Screenshot failed' });
    res.set('Content-Type', 'image/png');
    res.send(stdout);
  });
});

// ── Logs (last 100 lines) ────────────────────────────────────────────────────
app.get('/api/logs/:service', (req, res) => {
  const allowed = ['emulator', 'x11vnc', 'websockify', 'nodeserver'];
  const { service } = req.params;
  if (!allowed.includes(service)) return res.status(403).json({ error: 'Invalid service' });
  const logPath = `/var/log/${service}.log`;
  if (!fs.existsSync(logPath)) return res.json({ lines: [] });
  exec(`tail -n 100 ${logPath}`, (err, stdout) => {
    res.json({ lines: stdout.split('\n').filter(Boolean) });
  });
});

// ── Catch-all → serve frontend ───────────────────────────────────────────────
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

server.listen(PORT, () => {
  console.log(`🚀 Android Emulator Web running on port ${PORT}`);
  console.log(`📱 VNC WebSocket on port ${VNC_WS_PORT}`);
});
