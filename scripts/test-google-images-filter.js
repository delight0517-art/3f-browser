const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const swift = fs.readFileSync(path.join(__dirname, '../Sources/ThreeFBrowser/FocusFenceSearchResultFilter.swift'), 'utf8');
const classifier = swift.match(/static let classifierSource = #"""([\s\S]*?)"""#/);
const template = swift.match(/return #"""([\s\S]*?)"""#/);
assert.ok(classifier, 'Swift classifier script exists');
assert.ok(template, 'Swift injected filter script exists');

function run(pageURL, href) {
  const rules = JSON.stringify({ blockedDomains: ['blocked.example'], blockedUrlParts: [], keywords: [], blockExceptions: [] });
  const script = template[1]
    .replace('\\#(json)', rules)
    .replace('\\#(classifierSource)', classifier[1]);
  const card = {
    dataset: {},
    innerText: 'Image result',
    style: { display: '', setProperty(name, value) { if (name === 'display') this.display = value; } }
  };
  const link = {
    href,
    innerText: '',
    getAttribute() { return null; },
    querySelector() { return { alt: 'Blocked result' }; },
    closest(selector) { return selector === 'div.isv-r' ? card : null; },
    parentElement: { parentElement: card }
  };
  const document = {
    documentElement: {},
    querySelectorAll(selector) { return selector === 'a[href]' ? [link] : []; }
  };
  const context = {
    URL,
    location: { hostname: 'www.google.com', href: pageURL },
    document,
    MutationObserver: class { observe() {} },
    requestAnimationFrame(callback) { callback(); },
    addEventListener() {}
  };
  vm.runInNewContext(script, context);
  return card;
}

const redirect = 'https://www.google.com/imgres?imgrefurl=' + encodeURIComponent('https://blocked.example/gallery');
assert.equal(run('https://www.google.com/search?q=x&tbm=isch', redirect).style.display, 'none',
  'Google Images redirects are classified by their source-page URL and hide the matching card');
assert.equal(run('https://www.google.com/search?q=x', redirect).style.display, '',
  'the same Google redirect is not treated as an image result on ordinary web search');
assert.equal(run('https://www.google.com/search?q=x&tbm=isch', 'https://allowed.example/gallery').style.display, '',
  'unblocked image source pages remain visible');

console.log('Google Images filter redirect, page-mode, and allow-list checks passed');
