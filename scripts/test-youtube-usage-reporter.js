const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../Sources/ThreeFBrowser/YouTubeUsageReporter.swift'), 'utf8');
const match = source.match(/static let script = #"""([\s\S]*?)"""#/);
assert.ok(match, 'Swift YouTubeUsageReporter script literal exists');

async function run(host, quotaBlocked = true) {
  let paused = 0;
  let now = 1;
  let timer;
  const listeners = {};
  const payloads = [];
  const video = {
    currentTime: 4, currentSrc: 'test-video', paused: false, ended: false,
    seeking: false, readyState: 4, playbackRate: 1,
    pause() { this.paused = true; paused += 1; }
  };
  const document = {
    visibilityState: 'visible',
    querySelectorAll(selector) { return selector === 'video' ? [video] : []; },
    addEventListener(name, handler) { listeners[name] = handler; }
  };
  const context = {
    window: {}, location: { hostname: host, href: `https://${host}/watch` }, document,
    performance: { now: () => now }, URL,
    fetch: async (url, options = {}) => {
      if (String(url).includes('/rules')) {
        return { ok: true, json: async () => ({ youtubeQuotaBlocked: quotaBlocked }) };
      }
      if (options.method === 'POST') payloads.push(JSON.parse(options.body));
      return { ok: true, json: async () => ({}) };
    },
    setInterval(callback) { timer = callback; }, addEventListener() {}, crypto: { randomUUID: () => 'test-report' }
  };
  vm.runInNewContext(match[1], context);
  await new Promise(resolve => setImmediate(resolve));
  return {
    video, listeners, payloads,
    async reportProgress() { now += 2000; video.currentTime += 2; await timer(); },
    get paused() { return paused; }
  };
}

(async () => {
  const unrelated = await run('video.example.com');
  assert.equal(unrelated.video.paused, false, 'quota block must not pause unrelated video');
  unrelated.listeners.play();
  assert.equal(unrelated.video.paused, false, 'play event must not pause unrelated video');

  const youtube = await run('m.youtube.com');
  assert.equal(youtube.video.paused, true, 'quota block must pause YouTube video');

  const music = await run('music.youtube.com');
  assert.equal(music.video.paused, false, 'YouTube Music is excluded from YouTube video quota');
  music.listeners.play();
  assert.equal(music.video.paused, false, 'play event must not pause YouTube Music');

  const usage = await run('youtube.com', false);
  await usage.reportProgress();
  assert.equal(usage.payloads.length, 1, 'observed YouTube playback is reported');
  assert.deepEqual(Object.keys(usage.payloads[0]).sort(),
    ['browser', 'host', 'playing', 'reportId', 'seconds', 'watchSeconds'].sort(),
    'usage telemetry contains aggregate playback fields only');
  assert.equal(usage.payloads[0].watchSeconds, 2);

  console.log('YouTube usage reporter host-pause and aggregate-privacy checks: 7 passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
