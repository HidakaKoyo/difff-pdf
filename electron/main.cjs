const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { app, BrowserWindow, dialog } = require('electron');
const { startServer, stopServer } = require('./server.cjs');

let serverState = null;
let quitting = false;
let cleanupInFlight = null;
let buildMeta = null;

function readPackageBuildMeta() {
  try {
    // packaged app でも app.asar 内の package.json を取得できる
    // eslint-disable-next-line global-require, import/no-dynamic-require
    return require('../package.json');
  } catch (_) {
    return {};
  }
}

function resolveGitShaForDev() {
  const result = spawnSync('git', ['rev-parse', '--short', 'HEAD'], {
    cwd: process.cwd(),
    encoding: 'utf8',
    timeout: 1500,
  });
  if (result.status === 0) {
    const sha = String(result.stdout || '').trim();
    if (sha) return sha;
  }
  return 'nogit';
}

function resolveBuildTimeFallback() {
  try {
    const asarPath = path.join(process.resourcesPath, 'app.asar');
    const st = fs.statSync(asarPath);
    return st.mtime.toISOString();
  } catch (_) {
    return new Date().toISOString();
  }
}

function resolveBuildMeta() {
  const pkg = readPackageBuildMeta();
  const version = app.getVersion();

  let sha = process.env.DIFFF_BUILD_SHA || pkg.difffBuildSha || '';
  if (!sha) {
    sha = app.isPackaged ? 'nogit' : resolveGitShaForDev();
  }

  let buildTime = process.env.DIFFF_BUILD_TIME || pkg.difffBuildTime || '';
  if (!buildTime) {
    buildTime = resolveBuildTimeFallback();
  }

  const buildId = `${version}+${sha}@${buildTime}`;
  return {
    version,
    sha,
    buildTime,
    buildId,
  };
}

async function createMainWindow() {
  const window = new BrowserWindow({
    width: 1320,
    height: 900,
    minWidth: 980,
    minHeight: 720,
    backgroundColor: '#f4f8ff',
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.cjs'),
    },
  });

  await window.loadURL(serverState.appUrl);
  return window;
}

async function bootstrap() {
  buildMeta = resolveBuildMeta();
  try {
    serverState = await startServer({ buildId: buildMeta.buildId });
    await createMainWindow();
  } catch (err) {
    const detail = String(err && err.message ? err.message : err);
    const logPath = err && err.startupLogPath ? String(err.startupLogPath) : '';
    const lines = [
      `BUILD_ID: ${buildMeta.buildId}`,
      detail,
    ];
    if (logPath) {
      lines.push(`startup.log: ${logPath}`);
    }
    dialog.showErrorBox('difff-pdf 起動エラー', lines.join('\n\n'));
    app.quit();
  }
}

app.whenReady().then(bootstrap);

app.on('activate', async () => {
  if (BrowserWindow.getAllWindows().length === 0 && serverState) {
    await createMainWindow();
  }
});

app.on('before-quit', (event) => {
  if (quitting) return;
  quitting = true;
  event.preventDefault();
  cleanupInFlight = stopServer(serverState)
    .catch(() => {})
    .finally(() => {
      app.exit();
    });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

async function forceCleanupAndExit(code) {
  if (cleanupInFlight) {
    await cleanupInFlight;
    return;
  }
  try {
    await stopServer(serverState);
  } catch (_) {
    // noop
  }
  process.exit(code);
}

process.on('SIGINT', () => {
  forceCleanupAndExit(0);
});

process.on('SIGTERM', () => {
  forceCleanupAndExit(0);
});
