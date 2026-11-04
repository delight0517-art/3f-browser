const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../Sources/ThreeFBrowser/YouTubeUsageReporter.swift'), 'utf8');
const match = source.match(/static let script = #"""([\s\S]*?)"""#/);
assert.ok(match, 'Swift YouTubeUsageReporter script literal exists');

async function run(host, quotaBlocked = true, { failFirstAck = false, videoAtStart = true } = {}) {
  let paused = 0;
  let now = 1;
  let timer;
  let currentQuotaBlocked = quotaBlocked;
  let videoPresent = videoAtStart;
  let acceptedReports = new Set();
  let serverWatchSeconds = 0;
  let serverDwellSeconds = 0;
  let rulesReads = 0;
  const listeners = {};
  const payloads = [];
  const bridge = {
    async postMessage(message) {
      if (message.type === 'policy') {
        rulesReads += 1;
        return { youtubeQuotaBlocked: currentQuotaBlocked };
      }
      if (message.type === 'report') {
        const report = message.report;
        payloads.push(report);
        if (!acceptedReports.has(report.reportId)) {
          acceptedReports.add(report.reportId);
          serverWatchSeconds += report.watchSeconds;
          serverDwellSeconds += report.seconds;
        }
        if (failFirstAck && payloads.length === 1) return { ok: false };
        return { ok: true };
      }
      return { ok: false };
    }
  };
  const video = {
    tagName: 'VIDEO', currentTime: 4, currentSrc: 'test-video', paused: !videoAtStart, ended: false,
    seeking: false, readyState: 4, playbackRate: 1,
    pause() { this.paused = true; paused += 1; }
  };
  const document = {
    visibilityState: 'visible',
    querySelectorAll(selector) { return selector === 'video' && videoPresent ? [video] : []; },
    addEventListener(name, handler) { listeners[name] = handler; }
  };
  const context = {
    window: { webkit: { messageHandlers: { threefYouTubeUsage: bridge } } },
    location: { hostname: host, href: `https://${host}/watch` }, document,
    performance: { now: () => now },
    setInterval(callback) { timer = callback; }, addEventListener() {}, crypto: { randomUUID: () => 'test-report' }
  };
  vm.runInNewContext(match[1], context);
  await new Promise(resolve => setImmediate(resolve));
  return {
    video, listeners, payloads,
    async reportProgress(seconds = 2) { now += seconds * 1000; video.currentTime += seconds; await timer(); },
    startPlayback() {
      videoPresent = true;
      video.paused = false;
      listeners.play?.({ target: video });
      listeners.playing?.({ target: video });
    },
    async pausePlayback() {
      video.paused = true;
      await listeners.pause?.({ target: video });
    },
    async advance(ms) { now += ms; await timer(); },
    setQuotaBlocked(value) { currentQuotaBlocked = value; },
    setHost(value) { context.location.hostname = value; },
    get paused() { return paused; },
    get rulesReads() { return rulesReads; },
    get serverWatchSeconds() { return serverWatchSeconds; },
    get serverDwellSeconds() { return serverDwellSeconds; }
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

  const usage = await run('youtube.com', false, { videoAtStart: false });
  await usage.reportProgress();
  assert.equal(usage.payloads.length, 0, 'a paused YouTube page does not send a usage report');
  usage.startPlayback();
  await usage.reportProgress();
  assert.equal(usage.payloads.length, 0, 'a short active interval is retained until playback pauses');
  await usage.pausePlayback();
  assert.equal(usage.payloads.length, 1, 'observed YouTube playback is reported');
  assert.deepEqual(Object.keys(usage.payloads[0]).sort(),
    ['browser', 'host', 'playing', 'reportId', 'seconds', 'watchSeconds'].sort(),
    'usage telemetry contains aggregate playback fields only');
  assert.equal(usage.payloads[0].watchSeconds, 2);

  const retry = await run('youtube.com', false, { failFirstAck: true });
  await retry.reportProgress();
  await retry.pausePlayback();
  await retry.advance(5000);
  assert.equal(retry.payloads.length, 2, 'an unacknowledged aggregate is retried');
  assert.equal(retry.payloads[0].reportId, retry.payloads[1].reportId,
    'the same aggregate keeps one report ID across retries');
  assert.equal(retry.serverWatchSeconds, 2, 'server deduplication prevents a lost-ack retry from double counting');

  const recovers = await run('youtube.com', true, { videoAtStart: false });
  recovers.setQuotaBlocked(false);
  await recovers.advance(31000);
  assert.equal(recovers.rulesReads, 2, 'a blocked page refreshes quota policy after the retry interval');
  recovers.startPlayback();
  await recovers.reportProgress();
  await recovers.pausePlayback();
  assert.equal(recovers.payloads.at(-1).watchSeconds, 2,
    'playback usage is reported after policy changes from blocked to allowed');

  const hostSwitch = await run('youtube.com', false);
  await hostSwitch.reportProgress(2);
  hostSwitch.setHost('music.youtube.com');
  await hostSwitch.reportProgress(5);
  assert.equal(hostSwitch.payloads.length, 0, 'YouTube playback accumulated before a host switch is not reported from YouTube Music');
  hostSwitch.setHost('youtube.com');
  await hostSwitch.reportProgress(2);
  await hostSwitch.pausePlayback();
  assert.equal(hostSwitch.payloads.length, 1);
  assert.equal(hostSwitch.payloads[0].watchSeconds, 2,
    'only playback observed while the active page is on a YouTube watch host is reported');

  const reachesQuota = await run('youtube.com', false);
  assert.equal(reachesQuota.video.paused, false, 'under-cap YouTube playback remains allowed');
  reachesQuota.setQuotaBlocked(true);
  await reachesQuota.advance(31000);
  assert.equal(reachesQuota.video.paused, true,
    'YouTube playback pauses after a refreshed policy reports the quota reached');

  console.log('YouTube usage reporter host, playback, privacy, retry dedupe, and quota refresh checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
