const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../Sources/ThreeFBrowser/YouTubeUsageReporter.swift'), 'utf8');
const match = source.match(/static let script = #"""([\s\S]*?)"""#/);
assert.ok(match, 'Swift YouTubeUsageReporter script literal exists');

async function run(host, quotaBlocked = true, {
  failFirstAck = false, videoAtStart = true, playbackRate = 1, remainingSeconds = -1,
  accountLeaseUnsupported = true, failFirstLeaseAck = false
} = {}) {
  let paused = 0;
  let now = 1;
  let timer;
  let currentQuotaBlocked = quotaBlocked;
  let currentRemainingSeconds = remainingSeconds;
  let videoPresent = videoAtStart;
  let acceptedReports = new Set();
  let serverWatchSeconds = 0;
  let serverDwellSeconds = 0;
  let rulesReads = 0;
  const epoch = 1_800_000_000_000;
  const listeners = {};
  const payloads = [];
  const leaseRequests = [];
  const leaseReports = [];
  let leaseReportAttempts = 0;
  const bridge = {
    async postMessage(message) {
      if (message.type === 'policy') {
        rulesReads += 1;
        return { youtubeQuotaBlocked: currentQuotaBlocked, remainingSeconds: currentRemainingSeconds };
      }
      if (message.type === 'report') {
        const report = message.report;
        payloads.push(report);
        if (!acceptedReports.has(report.reportId)) {
          acceptedReports.add(report.reportId);
          serverWatchSeconds += report.watchSeconds;
          serverDwellSeconds += report.seconds;
          if (currentRemainingSeconds >= 0) {
            currentRemainingSeconds = Math.max(0, currentRemainingSeconds - report.watchSeconds);
            if (currentRemainingSeconds === 0) currentQuotaBlocked = true;
          }
        }
        if (failFirstAck && payloads.length === 1) return { ok: false };
        return { ok: true };
      }
      if (message.type === 'lease') {
        leaseRequests.push(message);
        if (accountLeaseUnsupported) {
          return { ok: false, status: 400, error: 'invalid_youtube_lease_request' };
        }
        const startMs = epoch + now;
        return {
          ok: true, schemaVersion: 3, billingMode: 'minimum_5s_qualified_30s_account_lease_v1',
          qualificationMs: 5000, quantumMs: 30000, allowed: true,
          grantId: 'grant-test', startMs, endMs: startMs + 30000, serverNowMs: startMs
        };
      }
      if (message.type === 'leaseReport') {
        leaseReports.push(message.report);
        leaseReportAttempts += 1;
        if (failFirstLeaseAck && leaseReportAttempts === 1) return { queued: false };
        return { queued: true };
      }
      return { ok: false };
    }
  };
  const video = {
    tagName: 'VIDEO', currentTime: 4, currentSrc: 'test-video', paused: !videoAtStart, ended: false,
    seeking: false, readyState: 4, playbackRate,
    pause() { this.paused = true; paused += 1; },
    play() { this.paused = false; return Promise.resolve(); }
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
    Date: { now: () => epoch + now },
    setInterval(callback) { timer = callback; }, addEventListener() {}, crypto: { randomUUID: () => 'test-report' }
  };
  vm.runInNewContext(match[1], context);
  await new Promise(resolve => setImmediate(resolve));
  return {
    video, listeners, payloads, leaseRequests, leaseReports,
    async reportProgress(seconds = 2) { now += seconds * 1000; video.currentTime += seconds * video.playbackRate; await timer(); },
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
    get host() { return context.location.hostname; },
    seekTo(value) { video.currentTime = value; },
    async setVisibility(value) { document.visibilityState = value; await listeners.visibilitychange?.(); },
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

  const accelerated = await run('youtube.com', false, { playbackRate: 2 });
  await accelerated.reportProgress(5);
  await accelerated.pausePlayback();
  assert.equal(accelerated.payloads[0].watchSeconds, 5,
    'playback speed does not multiply elapsed viewing time');

  const seek = await run('youtube.com', false);
  seek.seekTo(1000);
  await seek.reportProgress(5);
  await seek.reportProgress(2);
  await seek.pausePlayback();
  assert.equal(seek.payloads[0].watchSeconds, 2,
    'a seek jump is excluded while later normal playback is counted');

  const hidden = await run('youtube.com', false);
  await hidden.setVisibility('hidden');
  await hidden.reportProgress(10);
  await hidden.pausePlayback();
  assert.equal(hidden.payloads.length, 0, 'hidden-page playback is not reported as foreground viewing');

  const reachesQuota = await run('youtube.com', false);
  assert.equal(reachesQuota.video.paused, false, 'under-cap YouTube playback remains allowed');
  reachesQuota.setQuotaBlocked(true);
  await reachesQuota.advance(31000);
  assert.equal(reachesQuota.video.paused, true,
    'YouTube playback pauses after a refreshed policy reports the quota reached');
  assert.equal(reachesQuota.host, 'youtube.com',
    'quota enforcement pauses playback without navigating away from the YouTube page');

  const exhausted = await run('youtube.com', false, { remainingSeconds: 0 });
  assert.equal(exhausted.video.paused, true,
    'a zero remaining allowance blocks playback even before the quota flag refreshes');

  const finalSeconds = await run('youtube.com', false, { videoAtStart: false, remainingSeconds: 3 });
  finalSeconds.startPlayback();
  await finalSeconds.reportProgress(1);
  await finalSeconds.reportProgress(1);
  await finalSeconds.reportProgress(1);
  assert.equal(finalSeconds.serverWatchSeconds, 3,
    'a report is clamped to the exact remaining server-reported quota');
  assert.equal(finalSeconds.video.paused, true,
    'playback pauses at the quota boundary without waiting for the five-second batch');
  assert.equal(finalSeconds.payloads.at(-1).watchSeconds, 3);

  const delayedTick = await run('youtube.com', false, { remainingSeconds: 3 });
  await delayedTick.reportProgress(5);
  assert.equal(delayedTick.serverWatchSeconds, 3,
    'even a delayed timer tick cannot report beyond the remaining allowance');

  const leased = await run('youtube.com', false, {
    videoAtStart: false, accountLeaseUnsupported: false, failFirstLeaseAck: true
  });
  leased.startPlayback();
  for (let i = 0; i < 4; i += 1) await leased.reportProgress(1);
  assert.equal(leased.leaseRequests.length, 0, 'the lease is not requested before five seconds of measured playback');
  await leased.reportProgress(1);
  assert.equal(leased.leaseRequests.length, 1, 'five seconds of measured playback qualifies one account lease request');
  assert.equal(leased.leaseRequests[0].qualificationMs, 5000);
  assert.equal(leased.video.paused, false, 'playback resumes after an allowed lease');
  assert.equal(leased.payloads.length, 0, 'account-lease mode does not also submit legacy device usage');
  for (let i = 0; i < 5; i += 1) await leased.reportProgress(1);
  assert.equal(leased.leaseReports.length, 1, 'measured lease intervals are reported after five seconds');
  assert.equal(leased.leaseReports[0].grantId, 'grant-test');
  assert.equal(leased.leaseReports[0].intervals.length, 1, 'adjacent measured playback intervals are unioned');
  assert.equal(leased.leaseReports[0].intervals[0][1] - leased.leaseReports[0].intervals[0][0], 5000);
  await leased.reportProgress(1);
  assert.equal(leased.leaseReports.length, 2, 'an unacknowledged lease report is retried');
  assert.equal(leased.leaseReports[0].reportId, leased.leaseReports[1].reportId,
    'the lease report keeps its idempotency key across retries');
  assert.deepEqual(leased.leaseReports[0].intervals, leased.leaseReports[1].intervals,
    'the retry sends the exact same measured interval batch');
  assert.equal(leased.payloads.length, 0, 'shared interval reports do not double-count through the legacy route');

  const legacyFallback = await run('youtube.com', false, {
    videoAtStart: false, accountLeaseUnsupported: true
  });
  legacyFallback.startPlayback();
  for (let i = 0; i < 5; i += 1) await legacyFallback.reportProgress(1);
  assert.equal(legacyFallback.leaseRequests.length, 1, 'the unsupported shared route is detected once');
  assert.equal(legacyFallback.payloads.length, 1, 'unsupported shared routes retain local usage reporting');
  assert.equal(legacyFallback.payloads[0].watchSeconds, 5);

  console.log('YouTube usage reporter legacy and account-lease playback, interval, retry, privacy, and quota checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
