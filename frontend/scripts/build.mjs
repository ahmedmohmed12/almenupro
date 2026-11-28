#!/usr/bin/env node
/**
 * Cross-platform Flutter web build (Windows-friendly; replaces bash-only flow).
 */
import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FRONTEND_DIR = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(FRONTEND_DIR, '..');

function projectRoot() {
  if (existsSync(path.join(REPO_ROOT, 'pubspec.yaml'))) return REPO_ROOT;
  if (existsSync(path.join(FRONTEND_DIR, 'pubspec.yaml'))) return FRONTEND_DIR;
  console.error(`Could not find pubspec.yaml under ${REPO_ROOT}`);
  process.exit(1);
}

function resolveApiBaseUrl() {
  if (process.env.API_BASE_URL?.trim()) {
    return process.env.API_BASE_URL.replace(/\/$/, '');
  }
  if (process.env.VITE_API_URL?.trim()) {
    const base = process.env.VITE_API_URL.replace(/\/$/, '');
    return base.endsWith('/api') ? base : `${base}/api`;
  }
  return 'https://backend.u-menus.com/api';
}

function flutterBin(projectRootDir) {
  const flutterHome = process.env.FLUTTER_HOME || path.join(projectRootDir, '.flutter');
  const isWin = process.platform === 'win32';
  const bin = path.join(flutterHome, 'bin', isWin ? 'flutter.bat' : 'flutter');
  if (existsSync(bin)) return bin;
  return isWin ? 'flutter.bat' : 'flutter';
}

function run(cmd, args, opts = {}) {
  const useShell = process.platform === 'win32' && /\.bat$/i.test(cmd);
  const result = spawnSync(cmd, args, {
    stdio: 'inherit',
    shell: useShell,
    ...opts,
  });
  if (result.error) {
    console.error(result.error);
    process.exit(1);
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function copyIfExists(src, dest) {
  if (existsSync(src)) cpSync(src, dest);
}

const PROJECT_ROOT = projectRoot();
const DIST_DIR = path.join(FRONTEND_DIR, 'dist');
const API_BASE_URL = resolveApiBaseUrl();
let frontendBaseUrl = (
  process.env.FRONTEND_BASE_URL ||
  process.env.FRONTEND_URL ||
  'https://u-menus.com'
).replace(/\/$/, '');

const flutter = flutterBin(PROJECT_ROOT);
const webOut = path.join(PROJECT_ROOT, 'build', 'web');

run(flutter, ['config', '--enable-web', '--no-analytics'], { cwd: PROJECT_ROOT });
run(flutter, ['precache', '--web'], { cwd: PROJECT_ROOT });
run(flutter, ['pub', 'get'], { cwd: PROJECT_ROOT });
run(
  flutter,
  [
    'build',
    'web',
    '--release',
    `--dart-define=API_BASE_URL=${API_BASE_URL}`,
    `--dart-define=FRONTEND_BASE_URL=${frontendBaseUrl}`,
  ],
  { cwd: PROJECT_ROOT },
);

if (!existsSync(webOut)) {
  console.error(`Missing build output: ${webOut}`);
  process.exit(1);
}

rmSync(DIST_DIR, { recursive: true, force: true });
mkdirSync(DIST_DIR, { recursive: true });
cpSync(webOut, DIST_DIR, { recursive: true });

let siteHome = process.env.SITE_HOME || '';
if (!siteHome && frontendBaseUrl.includes('almenupro.pages.dev')) {
  siteHome = 'app';
}

const landingDir = path.join(FRONTEND_DIR, 'landing');
const landingIndex = path.join(landingDir, 'index.html');
if (existsSync(landingIndex)) {
  copyIfExists(landingIndex, path.join(DIST_DIR, 'landing.html'));
  const distIndex = path.join(DIST_DIR, 'index.html');
  if (siteHome === 'app') {
    if (existsSync(distIndex)) cpSync(distIndex, path.join(DIST_DIR, 'app.html'));
  } else if (existsSync(distIndex)) {
    cpSync(distIndex, path.join(DIST_DIR, 'app.html'));
    cpSync(landingIndex, distIndex);
  }
}

copyIfExists(path.join(landingDir, 'customers.html'), path.join(DIST_DIR, 'customers.html'));
copyIfExists(path.join(landingDir, 'smart-seller.html'), path.join(DIST_DIR, 'smart-seller.html'));
copyIfExists(path.join(landingDir, 'create.html'), path.join(DIST_DIR, 'create.html'));
copyIfExists(path.join(landingDir, 'i18n.js'), path.join(DIST_DIR, 'i18n.js'));

if (existsSync(path.join(PROJECT_ROOT, 'web', 'logo.png'))) {
  copyIfExists(path.join(PROJECT_ROOT, 'web', 'logo.png'), path.join(DIST_DIR, 'logo.png'));
} else {
  copyIfExists(path.join(landingDir, 'logo.png'), path.join(DIST_DIR, 'logo.png'));
}

copyIfExists(path.join(FRONTEND_DIR, 'public', '_redirects'), path.join(DIST_DIR, '_redirects'));

console.log(`Flutter web build complete: ${DIST_DIR}`);
console.log(`API_BASE_URL=${API_BASE_URL} FRONTEND_BASE_URL=${frontendBaseUrl}`);