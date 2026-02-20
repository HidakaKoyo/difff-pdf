const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const os = require('node:os');
const { spawn, spawnSync } = require('node:child_process');
const { app } = require('electron');

function readEnvInt(name, fallback) {
  const raw = process.env[name];
  if (typeof raw !== 'string' || raw.trim() === '') return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

const DEFAULT_PORT = readEnvInt('DIFFF_DESKTOP_PORT', 18765);
const READY_TIMEOUT_MS = Math.max(
  10_000,
  readEnvInt('DIFFF_DESKTOP_READY_TIMEOUT_SEC', readEnvInt('DIFFF_DESKTOP_STARTUP_TIMEOUT_SEC', 120)) * 1000
);
const UV_SYNC_TIMEOUT_MS = Math.max(10_000, readEnvInt('DIFFF_DESKTOP_UV_SYNC_TIMEOUT_SEC', 180) * 1000);
const HTTP_TIMEOUT_MS = 1500;
const READY_MARKER_RE = /id=['"]compare-form['"]/;

function resolveSourceRoot() {
  if (process.env.DIFFF_DESKTOP_ROOT && process.env.DIFFF_DESKTOP_ROOT.trim() !== '') {
    return path.resolve(process.env.DIFFF_DESKTOP_ROOT);
  }
  if (app && app.isPackaged) {
    return path.join(process.resourcesPath, 'app.asar.unpacked');
  }
  return path.resolve(process.cwd());
}

function resolveRuntimeRoot() {
  if (process.env.DIFFF_DESKTOP_RUNTIME_ROOT && process.env.DIFFF_DESKTOP_RUNTIME_ROOT.trim() !== '') {
    return path.resolve(process.env.DIFFF_DESKTOP_RUNTIME_ROOT);
  }
  if (process.platform === 'darwin') {
    return path.join(os.homedir(), 'Library', 'Application Support', 'difff-pdf', 'runtime');
  }
  if (app && app.isPackaged) {
    return path.join(app.getPath('userData'), 'runtime');
  }
  return path.join(os.tmpdir(), `difff-pdf-runtime-${process.pid}`);
}

function resolveStartupLogPath() {
  if (process.platform === 'darwin') {
    return path.join(os.homedir(), 'Library', 'Application Support', 'difff-pdf', 'logs', 'startup.log');
  }

  let userDataDir = '';
  try {
    userDataDir = app.getPath('userData');
  } catch (_) {
    userDataDir = '';
  }
  const root = userDataDir && userDataDir.trim() !== ''
    ? userDataDir
    : path.join(os.tmpdir(), 'difff-pdf');
  return path.join(root, 'logs', 'startup.log');
}

function rotateLogIfNeeded(logPath) {
  try {
    if (!fs.existsSync(logPath)) return;
    const st = fs.statSync(logPath);
    if (st.size < 1024 * 1024) return;
    const backup = `${logPath}.1`;
    if (fs.existsSync(backup)) {
      fs.rmSync(backup, { force: true });
    }
    fs.renameSync(logPath, backup);
  } catch (_) {
    // noop
  }
}

function createLogger(buildId) {
  const logPath = resolveStartupLogPath();
  const write = (level, event, fields = {}) => {
    try {
      fs.mkdirSync(path.dirname(logPath), { recursive: true });
      rotateLogIfNeeded(logPath);
      const merged = {
        build_id: buildId,
        pid: process.pid,
        ...fields,
      };
      const body = Object.entries(merged)
        .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
        .join(' ');
      fs.appendFileSync(logPath, `${new Date().toISOString()} ${level} ${event} ${body}\n`, 'utf8');
    } catch (_) {
      // noop
    }
  };

  return {
    path: logPath,
    info(event, fields) {
      write('INFO', event, fields);
    },
    warn(event, fields) {
      write('WARN', event, fields);
    },
    error(event, fields) {
      write('ERROR', event, fields);
    },
  };
}

function shouldCopyPath(srcPath) {
  const base = path.basename(srcPath);
  if (base === '.venv' || base === '__pycache__' || base === '.DS_Store') {
    return false;
  }
  return true;
}

async function copyDirOverlay(srcDir, dstDir) {
  if (!fs.existsSync(srcDir)) return;
  await fsp.mkdir(dstDir, { recursive: true });
  await fsp.cp(srcDir, dstDir, {
    recursive: true,
    force: true,
    filter: shouldCopyPath,
  });
}

function writeWrapperIfMissing(filePath, targetScript) {
  if (fs.existsSync(filePath)) return;
  const body = `#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($Bin);
my $target = "$Bin/${targetScript}";
chdir "$Bin/.." or die "chdir failed: $!";
exec '/usr/bin/perl', $target or die "exec failed: $!";
`;
  fs.writeFileSync(filePath, body, { encoding: 'utf8', mode: 0o755 });
}

async function ensureRuntimeRoot(sourceRoot) {
  const runtimeRoot = resolveRuntimeRoot();

  await fsp.mkdir(runtimeRoot, { recursive: true });
  await fsp.mkdir(path.join(runtimeRoot, 'cgi-bin'), { recursive: true });
  await fsp.mkdir(path.join(runtimeRoot, 'data', 'tmp'), { recursive: true });
  await fsp.mkdir(path.join(runtimeRoot, 'docs'), { recursive: true });

  const rootFiles = ['difff.pl', 'index.cgi', 'favicon.ico', '.htaccess'];
  for (const name of rootFiles) {
    const src = path.join(sourceRoot, name);
    const dst = path.join(runtimeRoot, name);
    if (!fs.existsSync(src)) continue;
    await fsp.copyFile(src, dst);
    if (name.endsWith('.pl') || name.endsWith('.cgi')) {
      await fsp.chmod(dst, 0o755);
    }
  }

  await copyDirOverlay(path.join(sourceRoot, 'tools'), path.join(runtimeRoot, 'tools'));
  await copyDirOverlay(path.join(sourceRoot, 'static'), path.join(runtimeRoot, 'static'));

  const cgis = ['difff.pl', 'index.cgi'];
  for (const name of cgis) {
    const src = path.join(sourceRoot, 'cgi-bin', name);
    const dst = path.join(runtimeRoot, 'cgi-bin', name);
    if (fs.existsSync(src)) {
      await fsp.copyFile(src, dst);
      await fsp.chmod(dst, 0o755);
    } else {
      writeWrapperIfMissing(dst, `../${name}`);
    }
  }

  const dataReadme = path.join(sourceRoot, 'data', 'README.md');
  if (fs.existsSync(dataReadme)) {
    await fsp.copyFile(dataReadme, path.join(runtimeRoot, 'data', 'README.md'));
  }

  return runtimeRoot;
}

function validateProjectPython(projectEnv) {
  const py = path.join(projectEnv, 'bin', 'python3');
  if (!fs.existsSync(py)) return false;
  const result = spawnSync(py, ['-V'], { encoding: 'utf8' });
  return result.status === 0;
}

function isTimedOut(result) {
  if (!result) return false;
  return Boolean(result.error && (result.error.code === 'ETIMEDOUT' || /timed out/i.test(String(result.error.message || ''))));
}

function summarizeRunResult(result) {
  if (!result) return 'no result';
  const chunks = [];
  if (result.status !== null && result.status !== undefined) {
    chunks.push(`status=${result.status}`);
  }
  if (result.signal) chunks.push(`signal=${result.signal}`);
  if (result.error) chunks.push(`error=${result.error.message}`);
  const stdout = String(result.stdout || '').trim();
  const stderr = String(result.stderr || '').trim();
  if (stdout) chunks.push(`stdout=${stdout.slice(-2000)}`);
  if (stderr) chunks.push(`stderr=${stderr.slice(-2000)}`);
  return chunks.join(' | ');
}

function runUvSync(uvCmd, args, cwd, env) {
  return spawnSync(uvCmd, args, {
    cwd,
    env,
    encoding: 'utf8',
    timeout: UV_SYNC_TIMEOUT_MS,
    maxBuffer: 10 * 1024 * 1024,
  });
}

function ensureProjectEnvironment(uvCmd, runtimeRoot, logger) {
  const projectEnv = path.join(runtimeRoot, 'tools', '.venv');
  if (validateProjectPython(projectEnv)) {
    logger.info('uv.env.reuse', { project_env: projectEnv });
    return projectEnv;
  }

  try {
    if (fs.existsSync(projectEnv)) {
      fs.rmSync(projectEnv, { recursive: true, force: true });
    }
  } catch (_) {
    // noop
  }

  const syncEnv = {
    ...process.env,
    UV_PROJECT_ENVIRONMENT: projectEnv,
  };

  logger.info('uv.sync.start', {
    uv_cmd: uvCmd,
    timeout_ms: UV_SYNC_TIMEOUT_MS,
    mode: 'offline-first',
  });

  let result = runUvSync(
    uvCmd,
    ['sync', '--project', 'tools', '--offline', '--no-python-downloads'],
    runtimeRoot,
    syncEnv
  );

  if (isTimedOut(result)) {
    throw new Error(`uv sync timed out. ${summarizeRunResult(result)}`);
  }

  if (result.status !== 0) {
    logger.warn('uv.sync.offline.failed', {
      detail: summarizeRunResult(result),
    });
    result = runUvSync(uvCmd, ['sync', '--project', 'tools'], runtimeRoot, syncEnv);
    if (isTimedOut(result)) {
      throw new Error(`uv sync timed out. ${summarizeRunResult(result)}`);
    }
  }

  if (result.status !== 0) {
    throw new Error(`uv sync failed. ${summarizeRunResult(result)}`);
  }

  if (!validateProjectPython(projectEnv)) {
    throw new Error(`python in project environment is not usable: ${projectEnv}`);
  }

  logger.info('uv.sync.ok', { project_env: projectEnv });
  return projectEnv;
}

function fetchHttp(url, maxBytes = 65536) {
  return new Promise((resolve) => {
    let target;
    try {
      target = new URL(url);
    } catch (err) {
      resolve({
        ok: false,
        status: 0,
        body: '',
        contentType: '',
        error: `invalid_url: ${String(err && err.message ? err.message : err)}`,
      });
      return;
    }

    const req = http.request({
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port,
      path: `${target.pathname}${target.search}`,
      method: 'GET',
      insecureHTTPParser: true,
    }, (res) => {
      const chunks = [];
      let size = 0;

      res.on('data', (chunk) => {
        if (size >= maxBytes) return;
        const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        const remain = maxBytes - size;
        chunks.push(remain >= buf.length ? buf : buf.subarray(0, remain));
        size += buf.length;
      });

      res.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf8');
        resolve({
          ok: true,
          status: res.statusCode || 0,
          body,
          contentType: String((res.headers && res.headers['content-type']) || ''),
        });
      });
    });

    req.on('error', (err) => {
      resolve({
        ok: false,
        status: 0,
        body: '',
        contentType: '',
        error: String(err && err.message ? err.message : err),
      });
    });

    req.setTimeout(HTTP_TIMEOUT_MS, () => {
      req.destroy(new Error(`timeout(${HTTP_TIMEOUT_MS}ms)`));
    });
    req.end();
  });
}

function summarizeHttpResult(result) {
  if (!result) return 'no-result';
  if (!result.ok) {
    return `error=${result.error || 'request-failed'}`;
  }
  const body = String(result.body || '').replace(/\s+/g, ' ').slice(0, 240);
  return `status=${result.status} content_type=${String(result.contentType || '')} body=${body}`;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitUntilReady(rootUrl, cgiUrl, timeoutMs, getErrorDetail, logger) {
  const started = Date.now();
  let lastRoot = '';
  let lastCgi = '';

  while (Date.now() - started < timeoutMs) {
    const rootResult = await fetchHttp(rootUrl, 2048);
    lastRoot = summarizeHttpResult(rootResult);

    if (rootResult.ok) {
      const cgiResult = await fetchHttp(cgiUrl, 65536);
      lastCgi = summarizeHttpResult(cgiResult);
      const isHtml = /text\/html/i.test(String(cgiResult.contentType || ''));
      const markerFound =
        cgiResult.ok &&
        cgiResult.status === 200 &&
        isHtml &&
        READY_MARKER_RE.test(String(cgiResult.body || ''));

      if (markerFound) {
        logger.info('ready.ok', {
          root: lastRoot,
          cgi_status: cgiResult.status,
          marker: 'compare-form',
        });
        return;
      }
    }

    await sleep(250);
  }

  const detail = [
    `root_probe=${lastRoot}`,
    `cgi_probe=${lastCgi}`,
    getErrorDetail ? getErrorDetail() : '',
  ]
    .filter((v) => v && v.trim() !== '')
    .join('\n');

  throw new Error(`CGI server did not become ready: ${cgiUrl}${detail ? `\n${detail}` : ''}`);
}

function withErrorLogPath(err, logger) {
  if (err && logger && logger.path) {
    try {
      err.startupLogPath = logger.path;
    } catch (_) {
      // noop
    }
  }
  return err;
}

function canBindPort(port) {
  return new Promise((resolve) => {
    const tester = net.createServer();
    tester.unref();

    tester.once('error', () => {
      resolve(false);
    });

    tester.listen(port, () => {
      tester.close(() => resolve(true));
    });
  });
}

function pickRandomPort() {
  return new Promise((resolve, reject) => {
    const tester = net.createServer();
    tester.unref();

    tester.once('error', (err) => {
      reject(err);
    });

    tester.listen(0, () => {
      const address = tester.address();
      const port = address && typeof address === 'object' ? address.port : 0;
      tester.close(() => {
        if (port > 0) resolve(port);
        else reject(new Error('failed to allocate random port'));
      });
    });
  });
}

async function resolveListenPort(preferredPort, logger) {
  if (Number.isInteger(preferredPort) && preferredPort > 0 && preferredPort <= 65535) {
    const available = await canBindPort(preferredPort);
    if (available) {
      return { port: preferredPort, fallback: false };
    }
    const randomPort = await pickRandomPort();
    logger.warn('port.fallback', {
      reason: 'preferred_port_busy',
      preferred_port: preferredPort,
      selected_port: randomPort,
    });
    return { port: randomPort, fallback: true };
  }

  const randomPort = await pickRandomPort();
  logger.warn('port.fallback', {
    reason: 'preferred_port_invalid',
    preferred_port: preferredPort,
    selected_port: randomPort,
  });
  return { port: randomPort, fallback: true };
}

async function startServer(options = {}) {
  const buildId = options.buildId || 'unknown';
  const logger = createLogger(buildId);

  try {
    const sourceRoot = resolveSourceRoot();
    const runtimeRoot = await ensureRuntimeRoot(sourceRoot);
    const uvCmd = process.env.DIFFF_UV_CMD || '/opt/homebrew/bin/uv';

    logger.info('startup.begin', {
      source_root: sourceRoot,
      runtime_root: runtimeRoot,
      preferred_port: DEFAULT_PORT,
      ready_timeout_ms: READY_TIMEOUT_MS,
      uv_sync_timeout_ms: UV_SYNC_TIMEOUT_MS,
      uv_cmd: uvCmd,
    });

    if (!fs.existsSync(uvCmd)) {
      throw new Error(`uv command not found: ${uvCmd}`);
    }

    const projectEnv = ensureProjectEnvironment(uvCmd, runtimeRoot, logger);
    const portInfo = await resolveListenPort(DEFAULT_PORT, logger);
    const port = portInfo.port;

    const args = ['run', '--project', 'tools', 'python', '-m', 'http.server', '--cgi', String(port)];
    const child = spawn(uvCmd, args, {
      cwd: runtimeRoot,
      env: {
        ...process.env,
        UV_PROJECT_ENVIRONMENT: projectEnv,
        DIFFF_BASE_URL: `http://127.0.0.1:${port}/cgi-bin/`,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let startupError = '';
    child.stderr.on('data', (chunk) => {
      startupError += String(chunk);
      if (startupError.length > 8000) {
        startupError = startupError.slice(-8000);
      }
    });
    child.stdout.on('data', () => {
      // drain stdout to avoid backpressure
    });

    child.once('exit', (code, signal) => {
      logger.warn('child.exit', {
        code,
        signal,
      });
    });

    const appUrl = `http://127.0.0.1:${port}/cgi-bin/difff.pl`;
    const rootUrl = `http://127.0.0.1:${port}/`;

    const exitPromise = new Promise((resolve) => {
      child.once('exit', (code, signal) => {
        resolve({ code, signal });
      });
    });

    try {
      await Promise.race([
        waitUntilReady(rootUrl, appUrl, READY_TIMEOUT_MS, () => startupError.trim(), logger),
        exitPromise.then((info) => {
          throw new Error(`CGI server exited early (code=${info.code}, signal=${info.signal}). ${startupError}`);
        }),
      ]);
    } catch (err) {
      if (!child.killed) child.kill('SIGTERM');
      throw err;
    }

    logger.info('startup.ready', {
      app_url: appUrl,
      fallback_port: portInfo.fallback,
      port,
      command: `${uvCmd} ${args.join(' ')}`,
    });

    return {
      child,
      port,
      appUrl,
      root: runtimeRoot,
      sourceRoot,
      projectEnv,
      command: `${uvCmd} ${args.join(' ')}`,
      startupLogPath: logger.path,
      buildId,
    };
  } catch (err) {
    logger.error('startup.failed', {
      error: err && err.message ? err.message : String(err),
    });
    throw withErrorLogPath(err, logger);
  }
}

async function stopServer(server) {
  if (!server || !server.child || server.child.killed) return;

  const proc = server.child;
  proc.kill('SIGTERM');

  await Promise.race([
    new Promise((resolve) => proc.once('exit', () => resolve())),
    new Promise((resolve) => {
      setTimeout(() => {
        if (!proc.killed) proc.kill('SIGKILL');
        resolve();
      }, 3000);
    }),
  ]);

  if (server.startupLogPath) {
    try {
      fs.mkdirSync(path.dirname(server.startupLogPath), { recursive: true });
      fs.appendFileSync(
        server.startupLogPath,
        `${new Date().toISOString()} INFO shutdown.complete build_id=${JSON.stringify(server.buildId || 'unknown')} pid=${JSON.stringify(process.pid)}\n`,
        'utf8'
      );
    } catch (_) {
      // noop
    }
  }
}

module.exports = {
  startServer,
  stopServer,
};
