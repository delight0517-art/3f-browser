#!/usr/bin/env node
'use strict';

/**
 * Attach-only QA preview server check. This verifies the app through
 * workflow-control, then exercises the isolated DesktopServer QA status path;
 * it never creates fixtures or launches the app.
 *
 * Before using this against an app, a fixture must be used to validate the
 * preview flow safely. This runtime intentionally does not create or start one.
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');

const execFileAsync = promisify(execFile);
const TIMEOUT_MS = 30_000;

function parseArgs(argv) {
  const opts = {};
  const names = ['app', 'source-root', 'descriptor', 'profile', 'executable', 'bundle-id'];
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    if (key === '--help' || key === '-h') return { help: true };
    if (!key.startsWith('--') || i + 1 >= argv.length) throw new Error(`Invalid argument: ${key}`);
    const name = key.slice(2);
    if (!names.includes(name)) throw new Error(`Unknown option: ${key}`);
    if (Object.hasOwn(opts, name)) throw new Error(`Repeated option: ${key}`);
    opts[name] = argv[++i];
  }
  return opts;
}

function help() {
  process.stdout.write('Attach-only QA preview runtime\nUsage: node scripts/qa-preview-runtime.cjs --app PATH --source-root PATH --descriptor PATH --profile PATH --executable PATH --bundle-id QA_BUNDLE_ID\nUse a fixture before the app; this command does not create fixtures or launch the app.\n');
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) return help();
  for (const key of ['app', 'source-root', 'descriptor', 'profile', 'executable', 'bundle-id']) {
    if (!opts[key]) throw new Error(`Missing required --${key}`);
  }
  const bundleIdentifier = opts['bundle-id'];
  if (!/(^|\.)QA($|\.)/i.test(bundleIdentifier)) throw new Error('Bundle identifier must contain a QA segment');
  const appPath = path.resolve(opts.app);
  const sourceRoot = path.resolve(opts['source-root']);
  const descriptorPath = path.resolve(opts.descriptor);
  const profilePath = path.resolve(opts.profile);
  const executablePath = path.resolve(opts.executable);

  const verifyPath = path.join(os.homedir(), '.codex', 'bin', 'workflow-control');
  const { stdout } = await execFileAsync(verifyPath, ['verify-mac', appPath], { timeout: TIMEOUT_MS, maxBuffer: 1024 * 1024 });
  let verification;
  try { verification = JSON.parse(stdout); } catch { throw new Error('workflow-control verify-mac returned invalid JSON'); }
  if (!verification || verification.launchAllowed !== true) throw new Error('workflow-control did not confirm launchAllowed');

  const serverModulePath = path.join(sourceRoot, 'src', 'ui', 'desktop', 'server.js');
  if (!fs.existsSync(serverModulePath)) throw new Error(`DesktopServer module not found: ${serverModulePath}`);
  const { DesktopServer } = require(serverModulePath);
  if (typeof DesktopServer !== 'function') {
    throw new Error('DesktopServer interface unavailable');
  }

  const dataDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'threef-qa-preview-'));
  let server;
  try {
    server = new DesktopServer({
      port: 0,
      isolated: true,
      dataDir,
      threefQaTarget: { descriptorPath, profilePath, executablePath, bundleIdentifier },
    });
    await server.start();
    const status = await server.dispatchThreefQACommand({ action: 'status' });
    if (!status || !Number.isInteger(status.processIdentifier) || status.processIdentifier <= 0 || status.qaProfilePath !== profilePath) {
      throw new Error('QA status did not confirm expected processIdentifier and qaProfilePath');
    }
    process.stdout.write(`${JSON.stringify({ ok: true, processIdentifier: status.processIdentifier, qaProfilePath: status.qaProfilePath })}\n`);
  } finally {
    try {
      if (server) await server.stop();
    } finally {
      await fs.promises.rm(dataDir, { recursive: true, force: true });
    }
  }
}

if (require.main === module) main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
module.exports = { main, parseArgs };
