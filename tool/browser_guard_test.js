// 브라우저 웹 클라이언트의 네트워크 출구 검증. 프레임워크 없이
// Node 표준 라이브러리만 씀: 실제 assets/web/js/*.js를 vm에 올려 수동 입력부터
// 실제 URL 구성·fetch 옵션·redirect까지 검사함. 실행: `node tool/browser_guard_test.js`
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const http = require('node:http');
const path = require('node:path');
const assert = require('node:assert/strict');
require('./web_design_test.js');

const JS_DIR = path.join(__dirname, '../assets/web/js');
const read = (f) => fs.readFileSync(path.join(JS_DIR, f), 'utf8');
// vm 컨텍스트에서 만들어진 에러는 realm이 달라 instanceof가 안 맞아서 이름으로 봄
const isTypeError = (e) => e && e.name === 'TypeError';

/// socket.js가 로드 시점에 건드리는 DOM/브라우저 API를 최소한으로 흉내낸 컨텍스트
function makeContext({ origin = 'http://192.168.1.2:7890', fetchImpl, hash = '', storage, timers } = {}) {
  const windowEvents = {};
  const sockets = [];
  const instances = [];
  const statusEl = { textContent: '', className: '', style: {} };
  const el = (id) => (id === 'status' ? statusEl : { textContent: '', className: '', style: {} });
  class FakeWebSocket {
    constructor(url) { this.url = url; this.sent = []; this.readyState = 1; sockets.push(url); instances.push(this); }
    send(data) { this.sent.push(JSON.parse(data)); }
    close() {}
  }
  const ctx = {
    URL, Promise, Number, Math, Date, console,
    location: { href: origin + '/', origin, host: new URL(origin).host, protocol: 'http:', hash, pathname: '/', search: '' },
    history: { replaceState() {} },
    navigator: { language: 'en' },
    document: { getElementById: el },
    window: { addEventListener(name, fn) { (windowEvents[name] ||= []).push(fn); } },
    windowEvents,
    WebSocket: FakeWebSocket,
    setTimeout: timers ? (fn, ms) => timers.push({ fn, ms }) : setTimeout,
    clearTimeout,
    fetch: fetchImpl || (() => Promise.resolve({ ok: true })),
    sockets,
    instances,
    systemLines: [],
    system(text) { ctx.systemLines.push(text); },
  };
  if (storage) ctx.sessionStorage = storage;
  vm.createContext(ctx);
  for (const f of ['i18n.js', 'socket.js', 'peer_address.js']) {
    vm.runInContext(read(f), ctx, { filename: f });
  }
  return ctx;
}

function testEndpointParsing() {
  const ctx = makeContext();
  const ok = [
    ['10.0.0.1', 7890], ['172.16.0.1', 1], ['172.31.255.254', 65535],
    ['192.168.1.42', '7890'], ['10.255.255.255', 80],
  ];
  for (const [h, p] of ok) {
    const ep = ctx.parseLanEndpoint(h, p);
    assert.ok(ep, `${h}:${p} must be accepted`);
    assert.equal(ep.host, h);
    assert.equal(ep.port, Number(p));
  }
  const badHosts = [
    '010.0.0.1', '012.0.0.1', '0x0a.0.0.1', '10.1', '10.0.1', '167772161',
    '10.0.0.1.1', '10.0.0.256', '8.8.8.8', '127.0.0.1', '169.254.1.1',
    '172.15.0.1', '172.32.0.1', '192.169.1.1', '::1', 'localhost',
    '10.0.0.1@8.8.8.8', ' 10.0.0.1', '10.0.0.1 ', '', null, undefined, 10,
  ];
  for (const h of badHosts) {
    assert.equal(ctx.parseLanEndpoint(h, 7890), null, `host ${JSON.stringify(h)} must be rejected`);
  }
  const badPorts = [0, 65536, -1, 1.5, NaN, Infinity, '0x1F90', '07890', '', '65536', '1e3', null, undefined, '80 '];
  for (const p of badPorts) {
    assert.equal(ctx.parseLanEndpoint('10.0.0.1', p), null, `port ${JSON.stringify(p)} must be rejected`);
  }
}

function memoryStorage() {
  const map = new Map();
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    removeItem: (k) => map.delete(k),
    map,
  };
}

// 소켓이 열린 것만으로 '온라인'이 아님: 호스트의 첫 프레임(입장 승인) 뒤에만 온라인·재시도 초기화
// 받아 주지 않고 닫히면(포털 끔·새 코드) 재시도 없이 안내하고 탭에 둔 코드를 지움
function testEntryAcceptance() {
  const storage = memoryStorage();
  const timers = [];
  const ctx = makeContext({ hash: '#t=abc', storage, timers });
  assert.equal(storage.getItem('intragram-entry'), 'abc', 'the entry code is kept for this tab');
  const opens = [];
  ctx.connect(() => {}, (re) => opens.push(re), () => {});
  const ws = ctx.instances[0];
  ws.onopen();
  assert.equal(ws.sent[0].t, 'web_hello');
  assert.equal(ws.sent[0].tok, 'abc');
  assert.notEqual(vm.runInContext('statusEl.textContent', ctx), vm.runInContext('t("online")', ctx));
  assert.deepEqual(opens, [], 'an open socket is not an accepted guest');
  ws.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_state', count: 2 } }) });
  assert.equal(vm.runInContext('statusEl.textContent', ctx), vm.runInContext('t("online")', ctx));
  assert.deepEqual(opens, [false]);

  // 받아 준 뒤 끊김: 재시도
  ws.onclose();
  assert.equal(timers.length, 1, 'a dropped accepted guest retries');
  timers.shift().fn();
  const again = ctx.instances[1];
  again.onopen();
  again.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_state', count: 2 } }) });
  assert.deepEqual(opens, [false, true], 'the second entry is a reconnect');

  // 받아 주지 않고 닫힘: 재시도 없음, 안내, 코드 지움
  again.onclose();
  timers.shift().fn();
  const refused = ctx.instances[2];
  refused.onopen();
  refused.onclose();
  assert.equal(timers.length, 0, 'a refused entry code is not retried');
  assert.equal(vm.runInContext('statusEl.textContent', ctx), vm.runInContext('t("rejected")', ctx));
  assert.ok(ctx.systemLines.includes(vm.runInContext('t("rejected")', ctx)));
  assert.equal(storage.getItem('intragram-entry'), null);

  // 새로고침(주소에 #t= 없음): 이 탭에 둔 코드로 다시 들어감
  const reloadStorage = memoryStorage();
  reloadStorage.setItem('intragram-entry', 'kept');
  const reloaded = makeContext({ storage: reloadStorage });
  assert.equal(vm.runInContext('TOKEN', reloaded), 'kept');

  // 방이 꽉 참: 재시도 없이 이유를 보여 주고, 나중에 새로고침으로 들어오게 코드는 둠
  const fullStorage = memoryStorage();
  const fullTimers = [];
  const full = makeContext({ hash: '#t=abc', storage: fullStorage, timers: fullTimers });
  const fullOpens = [];
  full.connect(() => {}, (re) => fullOpens.push(re), () => {});
  const turnedAway = full.instances[0];
  turnedAway.onopen();
  turnedAway.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_full' } }) });
  turnedAway.onclose();
  assert.equal(fullTimers.length, 0, 'a full room is not knocked on again');
  assert.deepEqual(fullOpens, [], 'a full room is not an accepted guest');
  assert.equal(vm.runInContext('statusEl.textContent', full), vm.runInContext('t("roomFull")', full));
  assert.ok(full.systemLines.includes(vm.runInContext('t("roomFull")', full)));
  assert.equal(fullStorage.getItem('intragram-entry'), 'abc');
}

function testConnectAndUrls() {
  // 입장 토큰(#t=…)이 없으면 서버가 끊을 걸 알기에 소켓을 안 열고 이유를 보여 줌
  const bare = makeContext();
  bare.connect(() => {}, () => {}, () => {});
  assert.deepEqual(bare.sockets, [], 'no socket without an entry token');
  assert.equal(vm.runInContext('statusEl.textContent', bare), vm.runInContext('t("noToken")', bare));

  const ctx = makeContext({ hash: '#t=abc' });
  assert.equal(vm.runInContext('TOKEN', ctx), 'abc');
  ctx.connect(() => {}, () => {}, () => {});
  assert.deepEqual(ctx.sockets, ['ws://192.168.1.2:7890/ws'], 'only the serving host is dialled');

  assert.equal(ctx.endpointUrl({ host: '10.0.0.1', port: 80 }, '/ws', 'ws'), 'ws://10.0.0.1/ws');
  assert.equal(ctx.endpointUrl(null, '/ws', 'ws'), null);

  // 다운로드 URL: 명시된 주소가 틀리면 호스트로 몰래 바꾸지 않고 null
  assert.equal(ctx.resolveDownloadUrl('id', '010.0.0.1', 7890), null);
  assert.equal(ctx.resolveDownloadUrl('id', '8.8.8.8', 7890), null);
  assert.equal(ctx.resolveDownloadUrl('id', '127.0.0.1', 7890), null);
  assert.equal(ctx.resolveDownloadUrl('a/b', '10.0.0.5', 7890), 'http://10.0.0.5:7890/api/download/a%2Fb');
  assert.equal(ctx.resolveDownloadUrl('id', null, null), 'http://192.168.1.2:7890/api/download/id');

  // 사설 IPv4가 없어 링크 로컬·ULA로 뜬 호스트: 자기 주소를 실은 offer는 같은 출처로 받음 (남의 그런 주소는 여전히 거부)
  const linkLocal = makeContext({ origin: 'http://169.254.3.4:7890' });
  assert.equal(linkLocal.resolveDownloadUrl('id', '169.254.3.4', 7890), 'http://169.254.3.4:7890/api/download/id');
  assert.equal(linkLocal.resolveDownloadUrl('id', '169.254.3.4', 7891), null);
  assert.equal(linkLocal.resolveDownloadUrl('id', '169.254.9.9', 7890), null);
  const ula = makeContext({ origin: 'http://[fd00::5]:7890' });
  assert.equal(ula.resolveDownloadUrl('id', 'fd00::5', 7890), 'http://[fd00::5]:7890/api/download/id');
  assert.equal(ula.resolveDownloadUrl('id', 'fd00::6', 7890), null);
}

async function testPeerFetchOptions() {
  const calls = [];
  const ctx = makeContext({ fetchImpl: (url, opts) => { calls.push({ url, opts }); return Promise.resolve({ ok: true }); } });
  await ctx.peerFetch('http://10.0.0.5:7890/api/download/x', { redirect: 'follow', cache: 'default', headers: { a: 'b' } });
  await ctx.peerFetch('/api/download/x'); // 같은 origin(상대 경로)
  assert.equal(calls.length, 2);
  for (const c of calls) {
    assert.equal(c.opts.redirect, 'error', 'peer requests must never follow redirects');
    assert.equal(c.opts.cache, 'no-store');
  }
  assert.deepEqual({ ...calls[0].opts.headers }, { a: 'b' });

  for (const url of ['http://8.8.8.8/', 'http://127.0.0.1:7890/', 'https://192.168.1.5/', 'http://user:pw@10.0.0.1:7890/', 'ftp://10.0.0.1/', 'http://[::1]:7890/']) {
    await assert.rejects(ctx.peerFetch(url), isTypeError, `${url} must be refused`);
  }
  assert.equal(calls.length, 2, 'a refused URL never reaches fetch');
}


/// 브라우저 전송 흐름(v3 계약)을 실제 file_transfer.js/audio_player.js로 검사: offer는
/// at/md를 싣고, accept의 (id, at, tok)가 맞아야만 POST가 나가며(토큰·attempt·크기
/// 헤더, redirect:error), 받은 offer는 pull만 받아 헤더와 함께 GET한 뒤 file_received
/// ACK를 보냄. DOM은 접근성 속성·부모 관계·삭제만 기록하는 최소 스텁
function makeAppContext(fetchImpl) {
  const created = [];
  const sent = [];
  const byId = {};
  const windowEvents = {}, documentEvents = {};
  function find(root, selector) {
    const parts = selector.split(" ");
    function matches(el, part) {
      const cls = /\.([\w-]+)/.exec(part);
      const id = /\[data-id="([^"]+)"\]/.exec(part);
      return (!cls || (el.className || "").split(" ").includes(cls[1])) &&
        (!id || el.dataset && el.dataset.id === id[1]) &&
        (cls || id || el.tag === part);
    }
    function descendants(el) { return (el.children || []).flatMap(c => [c, ...descendants(c)]); }
    let candidates = [root];
    for (const part of parts) candidates = candidates.flatMap(descendants).filter(el => matches(el, part));
    return candidates[0] || null;
  }
  const makeEl = (tag) => {
    const el = {
      tag, tagName: tag.toUpperCase(), className: '', textContent: '', style: {}, children: [], dataset: {}, attributes: {}, listeners: {},
      classList: { add() {}, remove() {}, toggle() {} },
      appendChild(c) { this.children.push(c); c.parentNode = this; return c; },
      setAttribute(k, v) { this.attributes[k] = v; },
      removeAttribute(k) { delete this.attributes[k]; },
      remove() { if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((c) => c !== this); },
      addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); },
      querySelector(selector) { return find(this, selector); }, querySelectorAll() { return []; },
      insertBefore() {}, focus() { this.focused = true; }, click() {}, scrollTo() {}, contains() { return false; },
      pause() { this.paused = true; }, load() { this.loaded = true; },
    };
    if (tag === 'audio') Object.defineProperty(el, 'src', {
      get() { return this.attributes.src; }, set(value) { this.attributes.src = value; },
    });
    created.push(el);
    return el;
  };
  const objectUrls = [], revokedUrls = [];
  class FakeURL extends URL {
    static createObjectURL(b) { objectUrls.push(b); return 'blob:test-' + objectUrls.length; }
    static revokeObjectURL(url) { revokedUrls.push(url); }
  }
  const ctx = {
    URL: FakeURL, Promise, Number, Math, Date, console, AbortController, btoa, unescape,
    encodeURIComponent, setTimeout: (fn, ms) => ms >= 40000 ? 0 : setTimeout(fn, ms), clearTimeout, String, JSON, Object, Blob, objectUrls, revokedUrls, Uint8Array, windowEvents, documentEvents,
    // 소각 카운트다운은 등록만 기록 (실제 주기 실행은 안 함)
    intervals: [],
    setInterval(fn) { ctx.intervals.push(fn); return ctx.intervals.length; },
    clearInterval() {},
    location: { href: 'http://192.168.1.2:7890/', origin: 'http://192.168.1.2:7890', host: '192.168.1.2:7890', protocol: 'http:', hash: '', pathname: '/', search: '' },
    history: { replaceState() {} },
    navigator: { language: 'en', vibrate() {} },
    window: { matchMedia: () => ({ matches: true }), addEventListener(name, fn) { (windowEvents[name] ||= []).push(fn); } },
    document: {
      getElementById: (id) => byId[id] ||= makeEl('by-id'), createElement: makeEl, body: makeEl('body'),
      addEventListener(name, fn) { (documentEvents[name] ||= []).push(fn); },
      querySelector: () => makeEl('q'), createTextNode: (text) => ({ textContent: text }),
    },
    WebSocket: class {},
    fetch: fetchImpl, sent, created,
  };
  vm.createContext(ctx);
  for (const f of ['i18n.js', 'socket.js', 'peer_address.js', 'audio_player.js', 'chat_ui.js', 'chat_ui_handlers.js', 'file_transfer.js']) {
    vm.runInContext(read(f), ctx, { filename: f });
  }
  vm.runInContext('ws = { readyState: 1, close: function () {}, send: function (d) { sent.push(JSON.parse(d).d); } }; ready = true;', ctx);
  return ctx;
}

// 키보드가 이미 열린 초기 로드도 맞추되, CSS의 세그먼트 높이와 확대 접근성은 유지함
function testViewportFitKeepsFoldHeight() {
  for (const folded of [false, true]) {
    const ctx = makeAppContext(() => Promise.resolve({ ok: true }));
    let resize;
    ctx.window.visualViewport = { scale: 1, height: 300, addEventListener: (_, fn) => { resize = fn; } };
    ctx.window.matchMedia = (query) => ({
      matches: folded && query.includes('vertical-viewport-segments'),
      addEventListener() {},
    });
    vm.runInContext('fitToVisibleViewport()', ctx);
    assert.equal(ctx.document.body.style.maxHeight, '300px');
    assert.equal(ctx.document.body.style.height, undefined, 'CSS owns segment height');
    ctx.window.visualViewport.height = 180;
    resize();
    assert.equal(ctx.document.body.style.maxHeight, '180px');
    ctx.window.visualViewport.scale = 2;
    resize();
    assert.equal(ctx.document.body.style.maxHeight, '', 'pinch zoom remains usable');
  }
}

// 앱과 같은 기준: 내 글은 상대 읽음이 와야, 받은 글은 탭이 보여야 읽음·카운트다운이 시작됨
function testGuestBurnTiming() {
  const ctx = makeAppContext(() => Promise.resolve({ ok: true }));
  const started = () => Object.keys(vm.runInContext('timers', ctx));

  vm.runInContext('addBubble({ id: "mine1", mine: true, text: "hi", ttl: 5 })', ctx);
  assert.deepEqual(started(), [], 'my message does not burn before it is read');
  ctx.handleRead('mine1');
  assert.deepEqual(started(), ['mine1']);

  ctx.document.hidden = true;
  ctx.handleMsg({ id: 'in1', from: 'host', text: 'yo', ttl: 5 });
  assert.equal(ctx.sent.some((f) => f.k === 'read'), false, 'no read receipt from a hidden tab');
  assert.deepEqual(started(), ['mine1']);
  ctx.document.hidden = false;
  ctx.flushUnseen();
  assert.deepEqual({ ...ctx.sent.find((f) => f.k === 'read') }, { k: 'read', id: 'in1' });
  assert.deepEqual(started(), ['mine1', 'in1']);
}

// 여러 파일은 줄을 세워 하나씩 제안하고, 업로드를 취소하면 '취소됨'이 '실패'로 덮이지 않음
async function testGuestFileQueue() {
  let rejectUpload;
  const ctx = makeAppContext(() => new Promise((_, reject) => { rejectUpload = reject; }));
  const offers = () => ctx.sent.filter((f) => f.k === 'file_offer');
  ctx.offerFiles([{ name: 'a.txt', size: 1 }, { name: 'b.txt', size: 2 }]);
  assert.deepEqual(offers().map((f) => f.name), ['a.txt'], 'one offer at a time');
  ctx.handleFileReject({ id: offers()[0].id, at: offers()[0].at });
  assert.deepEqual(offers().map((f) => f.name), ['a.txt', 'b.txt'], 'the next file follows a decline');

  const b = offers()[1];
  ctx.handleFileAccept({ id: b.id, at: b.at, tok: 't' });
  const cancel = ctx.created.filter((e) => e.tag === 'button' && e.className === 'btn btn-ghost').pop();
  cancel.onclick();
  const wrap = cancel.parentNode;
  const abort = new Error('aborted');
  abort.name = 'AbortError';
  rejectUpload(abort);
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(wrap.textContent, 'Transfer cancelled', 'a cancelled upload is not reported as failed');
}

async function testBrowserFileFlows() {
  const calls = [];
  const ctx = makeAppContext((url, opts) => {
    calls.push({ url, opts });
    return Promise.resolve({ ok: true, status: 200, blob: () => Promise.resolve({}) });
  });
  const file = { name: 'a.txt', size: 5 };

  // 보내기: offer는 at/md를 싣고, 낡은 attempt/모르는 id의 accept는 업로드를 못 시작함
  ctx.offerFile(file);
  const offer = ctx.sent.find((f) => f.k === 'file_offer');
  assert.ok(offer.at && offer.md === 'push' && offer.size === 5 && Number.isInteger(offer.size));
  const cancel = ctx.created.find((e) => e.tag === 'button' && e.className === 'btn btn-ghost');
  assert.equal(cancel.attributes['aria-label'], 'Cancel: a.txt');
  assert.ok(!cancel.disabled, 'Cancel must remain focusable while waiting');
  for (let el = cancel; el; el = el.parentNode) {
    assert.notEqual(el.attributes['aria-hidden'], 'true', 'Cancel must remain in the accessibility tree');
  }
  ctx.handleFileAccept({ id: offer.id, at: 'stale', tok: 'tok' });
  ctx.handleFileAccept({ id: 'other', at: offer.at, tok: 'tok' });
  assert.equal(calls.length, 0, 'a mismatched accept must not upload');
  ctx.handleFileAccept({ id: offer.id, at: offer.at, tok: 'tok-1' });
  assert.equal(calls.length, 1);
  const post = calls[0];
  assert.equal(post.url, 'http://192.168.1.2:7890/api/transfer');
  assert.equal(post.opts.method, 'POST');
  assert.equal(post.opts.redirect, 'error');
  assert.equal(post.opts.cache, 'no-store');
  assert.equal(post.opts.headers['x-transfer-id'], offer.id);
  assert.equal(post.opts.headers['x-transfer-attempt'], offer.at);
  assert.equal(post.opts.headers['x-transfer-token'], 'tok-1');
  assert.equal(post.opts.headers['x-file-size'], '5');
  ctx.handleFileAccept({ id: offer.id, at: offer.at, tok: 'tok-1' });
  assert.equal(calls.length, 1, 'an accept can only start one upload');

  // 받기: push offer는 즉시 거절, pull offer는 토큰·attempt·크기 헤더로 GET한 뒤 ACK
  ctx.sent.length = 0;
  ctx.incomingOffer({ id: 'p1', at: 'ap1', md: 'push', name: 'x', size: 1 });
  assert.deepEqual({ ...ctx.sent[0] }, { k: 'file_reject', id: 'p1', at: 'ap1' });

  ctx.sent.length = 0;
  calls.length = 0;
  const before = ctx.created.length;
  ctx.incomingOffer({ id: 'f1', at: 'af1', md: 'pull', tok: 'tk', sh: '10.0.0.5', sp: 7890, name: 'x.bin', size: 9 });
  const accept = ctx.created.slice(before).find((e) => e.className === 'btn btn-accent');
  accept.onclick();
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://10.0.0.5:7890/api/download/f1');
  assert.deepEqual({ ...calls[0].opts.headers }, { 'x-transfer-token': 'tk', 'x-transfer-attempt': 'af1', 'x-file-size': '9' });
  assert.equal(calls[0].opts.redirect, 'error');
  assert.deepEqual({ ...ctx.sent.find((f) => f.k === 'file_received') }, { k: 'file_received', id: 'f1', at: 'af1' });
  assert.equal(accept.parentNode.children.includes(accept), false, 'a completed download must not leave a disabled button');
  assert.equal(ctx.created.slice(before).find((e) => e.className === 'xfer-name').textContent, "x.bin received — check your browser's downloads");

  // WAN 주소가 박힌 offer는 요청 자체를 안 만듦
  calls.length = 0;
  const before2 = ctx.created.length;
  ctx.incomingOffer({ id: 'f2', at: 'af2', md: 'pull', tok: 'tk', sh: '8.8.8.8', sp: 7890, name: 'x.bin', size: 9 });
  ctx.created.slice(before2).find((e) => e.className === 'btn btn-accent').onclick();
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(calls.length, 0, 'a WAN source must never be fetched');
  assert.equal(ctx.created.slice(before2).find((e) => e.className === 'xfer-name').textContent, 'Download failed');

  // 음성: 서버가 재생목록 MIME을 붙여도 <audio>에는 WAV 타입 blob만 붙음
  const playlist = new Blob(['#EXTM3U\nhttp://203.0.113.9/a.ts\n'], { type: 'application/vnd.apple.mpegurl' });
  const voice = makeAppContext(() => Promise.resolve({ ok: true, status: 200, blob: () => Promise.resolve(playlist) }));
  voice.incomingOffer({ id: 'v1', at: 'av1', md: 'pull', tok: 'tk', sh: '10.0.0.5', sp: 7890, vc: true, name: 'voice.wav', size: 9 });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(voice.objectUrls.length, 1);
  assert.equal(voice.objectUrls[0].type, 'audio/wav', 'a peer-chosen playlist MIME must not reach <audio>');
}

// 스트림은 EOF 전 ACK하지 않으며, 취소·크기 불일치도 완료로 보고하지 않음
async function testStreamingDownloads() {
  for (const outcome of ['complete', 'cancel', 'short', 'oversize']) {
    let source, aborted = 0, request;
    const body = new ReadableStream({
      start(controller) { source = controller; },
      cancel() { aborted++; },
    });
    const ctx = makeAppContext((_, options) => {
      request = options;
      return Promise.resolve({ ok: true, body });
    });
    ctx.incomingOffer({ id: 'stream', at: 'attempt', md: 'pull', name: 'stream.bin', size: 10 });
    ctx.created.find(e => e.className === 'btn btn-accent').onclick();
    await new Promise(r => setTimeout(r, 0));
    source.enqueue(new Uint8Array([1, 2, 3, 4]));
    await new Promise(r => setTimeout(r, 0));
    const progress = ctx.created.find(e => e.className === 'xfer-progress');
    assert.equal(progress.textContent, '40% · 4 B');
    assert.equal(ctx.sent.some(f => f.k === 'file_received'), false, 'no ACK before EOF');
    if (outcome === 'cancel') {
      ctx.created.filter(e => e.className === 'btn btn-ghost').pop().onclick();
    } else {
      if (outcome !== 'short') source.enqueue(new Uint8Array(outcome === 'oversize' ? 7 : 6).fill(5));
      source.close();
    }
    await new Promise(r => setTimeout(r, 0));
    const label = ctx.created.find(e => e.className === 'xfer-name');
    assert.equal(ctx.sent.some(f => f.k === 'file_received'), outcome === 'complete');
    assert.equal(ctx.objectUrls.length, outcome === 'complete' ? 1 : 0);
    if (outcome === 'complete') {
      assert.deepEqual([...new Uint8Array(await ctx.objectUrls[0].arrayBuffer())], [1, 2, 3, 4, 5, 5, 5, 5, 5, 5]);
    } else if (outcome === 'cancel') {
      assert.equal(request.signal.aborted, true);
      assert.equal(aborted, 1, 'the stream is cancelled as well as the fetch');
      assert.equal(label.textContent, 'Transfer cancelled');
    } else assert.equal(label.textContent, 'Download failed');
    assert.equal(Object.keys(ctx.activeDownloads).length, 0);
    assert.equal(progress.parentNode.children.includes(progress), false);
  }

  // fetch 자체가 AbortError로 끝나도 실패 문구나 ACK로 취소를 덮지 않음
  let reject;
  const ctx = makeAppContext(() => new Promise((_, fail) => { reject = fail; }));
  ctx.incomingOffer({ id: 'abort', at: 'a', md: 'pull', name: 'a', size: 1 });
  ctx.created.find(e => e.className === 'btn btn-accent').onclick();
  ctx.created.filter(e => e.className === 'btn btn-ghost').pop().onclick();
  reject(Object.assign(new Error('aborted'), { name: 'AbortError' }));
  await new Promise(r => setTimeout(r, 0));
  assert.equal(ctx.created.find(e => e.className === 'xfer-name').textContent, 'Transfer cancelled');
  assert.equal(ctx.sent.some(f => f.k === 'file_received'), false);
}

async function testVoiceResourceLifetime() {
  for (const end of ['burn', 'timer', 'pagehide']) {
    const ctx = makeAppContext(() => Promise.resolve({ ok: true, blob: () => Promise.resolve(new Blob(['voice'])) }));
    let now = Date.now();
    ctx.Date = class extends Date { static now() { return now; } };
    ctx.incomingOffer({ id: 'voice', at: 'a', md: 'pull', vc: true, name: 'v.wav', size: 5 });
    await new Promise(r => setTimeout(r, 0));
    const audio = ctx.created.find(e => e.tag === 'audio');
    assert.equal(audio.src, 'blob:test-1');
    if (end === 'burn') ctx.handleBurn('voice');
    if (end === 'timer') {
      ctx.startBurn('voice', 1, { textContent: '' });
      now += 1100;
      ctx.intervals[0]();
    }
    if (end === 'pagehide') ctx.windowEvents.pagehide.forEach(fn => fn({ persisted: true }));
    assert.equal(audio.paused, true, end + ': stop playback');
    assert.equal(audio.loaded, true, end + ': release decoder bytes');
    assert.equal(audio.attributes.src, undefined);
    assert.deepEqual(ctx.revokedUrls, ['blob:test-1'], end + ': revoke immediately');
    ctx.releaseVoice('voice');
    assert.equal(ctx.revokedUrls.length, 1, 'cleanup is idempotent');
  }

  let finish, request;
  const pending = makeAppContext((_, opts) => {
    request = opts;
    return new Promise(resolve => { finish = resolve; });
  });
  pending.incomingOffer({ id: 'late', at: 'a', md: 'pull', vc: true, name: 'v.wav', size: 5 });
  pending.handleBurn('late');
  finish({ ok: true, blob: () => Promise.resolve(new Blob(['voice'])) });
  await new Promise(r => setTimeout(r, 0));
  assert.equal(request.signal.aborted, true);
  assert.equal(pending.objectUrls.length, 0, 'a late response cannot revive a burnt voice');
  assert.equal(pending.sent.some(f => f.k === 'file_received'), false);
}

async function testPagehideCancelsTransfers() {
  const ctx = makeAppContext((_, opts) => new Promise((resolve, reject) => {
    opts.signal.addEventListener('abort', () => reject(Object.assign(new Error('abort'), { name: 'AbortError' })));
  }));
  ctx.initFileTransfer();
  ctx.incomingOffer({ id: 'down', at: 'a', md: 'pull', name: 'd.bin', size: 2 });
  ctx.created.find(e => e.className === 'btn btn-accent').onclick();
  ctx.offerFiles([{ name: 'up.bin', size: 2 }, { name: 'queued.bin', size: 3 }]);
  const offer = ctx.sent.find(f => f.k === 'file_offer');
  ctx.handleFileAccept({ id: offer.id, at: offer.at, tok: 't' });
  ctx.windowEvents.pagehide.forEach(fn => fn({ persisted: true }));
  await new Promise(r => setTimeout(r, 0));
  assert.equal(ctx.created.find(e => e.className === 'xfer-name').textContent, 'Transfer cancelled');
  assert.equal(Object.keys(ctx.activeDownloads).length, 0);
  assert.equal(Object.keys(ctx.activeUploads).length, 0);
  assert.equal(ctx.sendQueue.length, 0);
  assert.equal(ctx.pendingSend, null);
  assert.equal(ctx.sent.filter(f => f.k === 'file_offer').length, 1, 'a frozen page does not offer queued files');
  assert.equal(ctx.sent.some(f => f.k === 'file_received'), false);
}

function testBfCacheReconnect() {
  const timers = [];
  const ctx = makeContext({ hash: '#t=abc', timers });
  const opens = [], closes = [];
  ctx.connect(() => {}, again => opens.push(again), () => closes.push(true));
  const first = ctx.instances[0];
  first.onopen();
  first.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_state' } }) });
  ctx.windowEvents.pagehide.forEach(fn => fn({ persisted: true }));
  first.onclose();
  assert.equal(ctx.isReady(), false);
  assert.equal(timers.length, 0, 'pagehide does not schedule reconnect or reject the token');
  ctx.windowEvents.pageshow.forEach(fn => fn({ persisted: true }));
  assert.equal(ctx.instances.length, 2, 'restore opens one fresh socket');
  const restored = ctx.instances[1];
  first.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_state' } }) });
  assert.equal(ctx.isReady(), false, 'the old socket cannot mark the restored page online');
  restored.onopen();
  restored.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_state' } }) });
  assert.equal(ctx.isReady(), true);
  assert.deepEqual(opens, [false, true]);
  ctx.windowEvents.pageshow.forEach(fn => fn({ persisted: false }));
  assert.equal(ctx.instances.length, 2, 'ordinary pageshow does not duplicate the socket');
}

function testDiscoverableReactionAndSlash() {
  const ctx = makeAppContext(() => Promise.resolve({ ok: true }));
  const bubble = ctx.addBubble({ id: 'like', mine: false, text: 'hello' });
  const action = ctx.created.find(e => e.className === 'btn reaction-action');
  assert.equal(action.attributes['aria-label'], 'Toggle like');
  action.onclick();
  assert.equal(action.attributes['aria-pressed'], 'true');
  action.onclick();
  assert.equal(action.attributes['aria-pressed'], 'false');
  assert.equal(bubble.parentNode.children[1], action, 'the action follows the bubble in keyboard order');
  ctx.initChatUi();
  const shortcut = ctx.documentEvents.keydown[0];
  for (const target of [{ tagName: 'TEXTAREA' }, { tagName: 'INPUT' }, { tagName: 'SELECT' }, { isContentEditable: true }]) {
    shortcut({ key: '/', target, preventDefault() { assert.fail('typing must not be intercepted'); } });
  }
  let prevented = false;
  shortcut({ key: '/', target: { tagName: 'DIV' }, preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(ctx.inputEl.focused, true);
}

// 브라우저 기본 동작 흉내: 이벤트는 부모를 거쳐 document까지 올라가고, <button>은 Enter keydown(반복 포함)과
// Space keyup이 detail 0인 click이 됨. preventDefault된 키는 click을 만들지 않음
function dispatchIn(ctx, el, type, init = {}) {
  const event = {
    type, target: el, detail: 0, ...init, defaultPrevented: false, stopped: false,
    preventDefault() { this.defaultPrevented = true; }, stopPropagation() { this.stopped = true; },
  };
  for (let node = el; node && !event.stopped; node = node.parentNode) {
    if (type === 'click' && node.onclick) node.onclick(event);
    for (const fn of (node.listeners && node.listeners[type]) || []) fn(event);
  }
  if (!event.stopped) for (const fn of ctx.documentEvents[type] || []) fn(event);
  return event;
}
function pressKey(ctx, el, key, repeats = 0) {
  for (let i = 0; i <= repeats; i++) {
    const down = dispatchIn(ctx, el, 'keydown', { key, repeat: i > 0 });
    if (el.tag === 'button' && key === 'Enter' && !down.defaultPrevented) dispatchIn(ctx, el, 'click');
  }
  const up = dispatchIn(ctx, el, 'keyup', { key });
  if (el.tag === 'button' && key === ' ' && !up.defaultPrevented) dispatchIn(ctx, el, 'click');
}

// 한 동작 = 반응 한 번(react 프레임 하나). 따로 누른 두 번은 그대로 두 번이고 전역 디바운스는 없음
function testReactionActivationCounts() {
  const ctx = makeAppContext(() => Promise.resolve({ ok: true }));
  ctx.initChatUi();
  const bubble = ctx.addBubble({ id: 'r', mine: false, text: 'hi' });
  const action = ctx.created.find(e => e.className === 'btn reaction-action');
  const reacts = () => ctx.sent.filter(f => f.k === 'react').length;
  const clicks = (el, n) => { for (let i = 1; i <= n; i++) dispatchIn(ctx, el, 'click', { detail: i }); };
  const cases = [
    ['button click', () => clicks(action, 1), 1],
    ['button double-click', () => { clicks(action, 2); dispatchIn(ctx, action, 'dblclick', { detail: 2 }); }, 1],
    ['button triple-click', () => clicks(action, 3), 1],
    ['two separate clicks', () => { clicks(action, 1); clicks(action, 1); }, 2],
    ['bubble double-click', () => { clicks(bubble, 2); dispatchIn(ctx, bubble, 'dblclick', { detail: 2 }); }, 1],
    ['button Enter', () => pressKey(ctx, action, 'Enter'), 1],
    ['button Space', () => pressKey(ctx, action, ' '), 1],
    ['button held Enter', () => pressKey(ctx, action, 'Enter', 5), 1],
    ['button held Space', () => pressKey(ctx, action, ' ', 5), 1],
    ['bubble Enter', () => pressKey(ctx, bubble, 'Enter'), 1],
    ['bubble Space', () => pressKey(ctx, bubble, ' '), 1],
    ['bubble held Enter', () => pressKey(ctx, bubble, 'Enter', 5), 1],
    ['bubble held Space', () => pressKey(ctx, bubble, ' ', 5), 1],
  ];
  for (const [name, act, expected] of cases) {
    const before = reacts();
    const pressed = action.attributes['aria-pressed'];
    act();
    assert.equal(reacts() - before, expected, name + ': react frames');
    const flipped = String(pressed !== 'true');
    assert.equal(action.attributes['aria-pressed'], expected % 2 ? flipped : pressed, name + ': state');
  }
  // 누르고 있는 동안의 반복 keydown은 스크롤·버튼 재실행 같은 기본 동작도 막힘
  assert.equal(dispatchIn(ctx, bubble, 'keydown', { key: ' ', repeat: true }).defaultPrevented, true);
  assert.equal(dispatchIn(ctx, action, 'keydown', { key: 'Enter', repeat: true }).defaultPrevented, true);
  assert.equal(dispatchIn(ctx, action, 'keydown', { key: 'Enter' }).defaultPrevented, false,
    'the first Enter keeps the native button activation');
  assert.equal(action.attributes['aria-label'], 'Toggle like');
}

// `/`는 조합 중·수정키·글 입력 요소에서는 그대로 두고, 그 밖에서만 입력창으로 초점을 옮김
function testSlashShortcutGuards() {
  const ctx = makeAppContext(() => Promise.resolve({ ok: true }));
  ctx.initChatUi();
  const shortcut = ctx.documentEvents.keydown[0];
  const div = { tagName: 'DIV' };
  for (const init of [
    { key: '/', ctrlKey: true, target: div }, { key: '/', metaKey: true, target: div },
    { key: '/', altKey: true, target: div }, { key: '/', isComposing: true, target: div },
    { key: 'Process', keyCode: 229, target: div }, { key: '?', shiftKey: true, target: div },
    { key: '/', target: { tagName: 'TEXTAREA' } }, { key: '/', target: { isContentEditable: true } },
  ]) {
    ctx.inputEl.focused = false;
    let prevented = false;
    shortcut({ ...init, preventDefault() { prevented = true; } });
    assert.equal(prevented, false, JSON.stringify(init));
    assert.equal(ctx.inputEl.focused, false, JSON.stringify(init));
  }
  // Shift로 `/`를 치는 배열(독일어 Shift+7 등)과 초점 둔 버튼에서는 입력창으로 감
  for (const target of [div, { tagName: 'BUTTON' }]) {
    ctx.inputEl.focused = false;
    let prevented = false;
    shortcut({ key: '/', shiftKey: true, target, preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
    assert.equal(ctx.inputEl.focused, true);
  }
}

// 완료 판정은 offer의 선언 크기로만 함: Content-Length가 없거나 틀려도, 빈 파일이어도 같음.
// 중간 오류·blob 폴백 크기 불일치는 ACK가 없고, 동시 전송은 서로의 상태를 안 건드림
async function testDownloadEdgeCases() {
  const tick = () => new Promise(r => setTimeout(r, 0));
  function streamed(ctx, id, size) {
    let source;
    const body = new ReadableStream({ start(c) { source = c; } });
    ctx.responses[id] = { ok: true, headers: { 'content-length': '999' }, body };
    const before = ctx.created.length;
    ctx.incomingOffer({ id, at: 'at-' + id, md: 'pull', name: id + '.bin', size });
    ctx.created.slice(before).find(e => e.className === 'btn btn-accent').onclick();
    const mine = ctx.created.slice(before);
    return {
      source: () => source,
      label: () => mine.find(e => e.className === 'xfer-name').textContent,
      cancel: () => mine.filter(e => e.className === 'btn btn-ghost').pop().onclick(),
    };
  }
  const make = () => {
    const responses = {};
    const ctx = makeAppContext((url) => Promise.resolve(responses[url.split('/').pop()]));
    ctx.responses = responses;
    return ctx;
  };
  const acks = (ctx, id) => ctx.sent.filter(f => f.k === 'file_received' && f.id === id).length;

  const empty = make();
  const e = streamed(empty, 'empty', 0);
  await tick();
  e.source().close();
  await tick();
  assert.equal(acks(empty, 'empty'), 1, 'an empty file is acknowledged once');
  assert.equal(empty.objectUrls[0].size, 0);

  const broken = make();
  const b = streamed(broken, 'broken', 8);
  await tick();
  const chunk = new Uint8Array([7, 7, 7, 7]);
  b.source().enqueue(chunk);
  await tick();
  b.source().error(new TypeError('network changed'));
  await tick();
  await tick();
  assert.equal(b.label(), 'Download failed');
  assert.equal(acks(broken, 'broken'), 0);
  assert.equal(broken.objectUrls.length, 0);
  assert.deepEqual([...chunk], [0, 0, 0, 0], 'received chunks are wiped after a failure');
  assert.equal(Object.keys(broken.activeDownloads).length, 0);

  for (const [size, ok] of [[5, true], [4, false]]) {
    const fallback = make();
    fallback.responses.blob = { ok: true, blob: () => Promise.resolve(new Blob(['12345'])) };
    fallback.incomingOffer({ id: 'blob', at: 'ab', md: 'pull', name: 'b.bin', size });
    fallback.created.find(el => el.className === 'btn btn-accent').onclick();
    await tick();
    await tick();
    assert.equal(acks(fallback, 'blob'), ok ? 1 : 0, 'blob fallback size ' + size);
    assert.equal(fallback.objectUrls.length, ok ? 1 : 0);
  }

  const both = make();
  const first = streamed(both, 'first', 2);
  const second = streamed(both, 'second', 2);
  await tick();
  first.source().enqueue(new Uint8Array([1]));
  second.source().enqueue(new Uint8Array([2]));
  await tick();
  first.cancel();
  second.source().enqueue(new Uint8Array([3]));
  second.source().close();
  await tick();
  await tick();
  assert.equal(first.label(), 'Transfer cancelled');
  assert.equal(second.label(), "second.bin received — check your browser's downloads");
  assert.deepEqual([acks(both, 'first'), acks(both, 'second')], [0, 1]);
  assert.deepEqual(both.sent.filter(f => f.k === 'file_cancel').map(f => f.id), ['first']);
  assert.equal(Object.keys(both.activeDownloads).length, 0);
}

// 숨김(pagehide) 때 회수한 음성은 BFCache 복귀 뒤에도 재생 가능한 척하지 않고, 다시 받지도 되살리지도 않음
async function testVoiceExpiryAcrossBfCache() {
  const tick = () => new Promise(r => setTimeout(r, 0));
  for (const lang of ['en', 'ko']) {
    let fetches = 0, finishLate;
    const ctx = makeAppContext((url) => {
      fetches++;
      if (url.endsWith('/late')) return new Promise(resolve => { finishLate = resolve; });
      return Promise.resolve({ ok: true, blob: () => Promise.resolve(new Blob(['voice'])) });
    });
    ctx.setLang(lang);
    ctx.incomingOffer({ id: 'played', at: 'a', md: 'pull', vc: true, name: 'v.wav', size: 5 });
    ctx.incomingOffer({ id: 'late', at: 'b', md: 'pull', vc: true, name: 'w.wav', size: 5 });
    await tick();
    const [played, late] = ctx.created.filter(el => el.tag === 'audio');
    const wraps = [played.parentNode, late.parentNode];
    assert.equal(played.src, 'blob:test-1');
    ctx.windowEvents.pagehide.forEach(fn => fn({ persisted: true }));
    for (const wrap of wraps) {
      assert.equal(wrap.children.some(el => el.tag === 'audio'), false, 'no playable control without a source');
      assert.equal(wrap.children[0].textContent,
        lang === 'ko' ? '음성 메시지 · 더 이상 재생할 수 없음' : 'Voice message · No longer available');
    }
    assert.deepEqual(ctx.revokedUrls, ['blob:test-1']);
    finishLate({ ok: true, blob: () => Promise.resolve(new Blob(['voice'])) });
    await tick();
    ctx.windowEvents.pageshow.forEach(fn => fn({ persisted: true }));
    await tick();
    assert.equal(fetches, 2, 'restoring the page downloads nothing again');
    assert.equal(ctx.objectUrls.length, 1, 'a late response cannot revive a released voice');
    assert.equal(ctx.sent.filter(f => f.k === 'file_received').length, 1);
    ctx.windowEvents.pagehide.forEach(fn => fn({ persisted: true }));
    assert.equal(ctx.revokedUrls.length, 1, 'a second pagehide changes nothing');
  }
}

// 숨김·복귀를 되풀이해도 리스너·소켓·재연결 타이머가 쌓이지 않음
function testBfCacheCycles() {
  const timers = [];
  const ctx = makeContext({ hash: '#t=abc', timers });
  const listeners = Object.fromEntries(Object.entries(ctx.windowEvents).map(([k, v]) => [k, v.length]));
  ctx.connect(() => {}, () => {}, () => {});
  for (let cycle = 1; cycle <= 3; cycle++) {
    const socket = ctx.instances[cycle - 1];
    socket.onopen();
    socket.onmessage({ data: JSON.stringify({ t: 'plain', d: { k: 'room_state' } }) });
    ctx.windowEvents.pagehide.forEach(fn => fn({ persisted: true }));
    socket.onclose();
    assert.equal(timers.length, 0, 'a hidden page schedules no reconnect');
    ctx.windowEvents.pageshow.forEach(fn => fn({ persisted: true }));
    assert.equal(ctx.instances.length, cycle + 1, 'each restore opens exactly one socket');
  }
  const after = Object.fromEntries(Object.entries(ctx.windowEvents).map(([k, v]) => [k, v.length]));
  assert.deepEqual(after, listeners, 'no window listener is added per cycle');
}

async function testDownloadStatusLocales() {
  for (const lang of ['ko', 'en']) {
    for (const failure of [null, 'url', 'response', 'network']) {
      const ctx = makeAppContext(() => failure === 'network'
        ? Promise.reject(new Error('offline'))
        : Promise.resolve({ ok: failure !== 'response', blob: () => Promise.resolve({}) }));
      ctx.setLang(lang);
      ctx.incomingOffer({ id: 'f', at: 'af', md: 'pull', name: 'a.txt', size: 5, sh: failure === 'url' ? '8.8.8.8' : '10.0.0.5', sp: 7890 });
      const accept = ctx.created.find((e) => e.className === 'btn btn-accent');
      accept.onclick();
      await new Promise((r) => setTimeout(r, 0));
      const label = ctx.created.find((e) => e.className === 'xfer-name');
      assert.equal(label.textContent, failure
        ? (lang === 'ko' ? '다운로드 실패' : 'Download failed')
        : (lang === 'ko'
          ? 'a.txt 받음. 브라우저 다운로드를 확인하세요'
          : "a.txt received — check your browser's downloads"));
      assert.equal(ctx.sent.some((f) => f.k === 'file_received'), !failure, 'only completed downloads send an ACK');
      if (!failure) assert.equal(accept.parentNode.children.includes(accept), false);
    }
  }
}

/// 진짜 HTTP로: peer가 3xx로 WAN 대역 서버를 가리켜도 토큰·본문이 그쪽에 가지 않음
async function testRedirectNeverLeaves() {
  const wanHits = [];
  const wan = http.createServer((req, res) => { wanHits.push({ method: req.method, token: req.headers['x-transfer-token'] }); res.end('leaked'); });
  await new Promise((r) => wan.listen(0, '127.0.0.1', r));
  const wanUrl = `http://127.0.0.1:${wan.address().port}/stolen`;
  const peer = http.createServer((req, res) => { req.resume(); res.writeHead(307, { location: wanUrl }); res.end(); });
  await new Promise((r) => peer.listen(0, '127.0.0.1', r));
  const peerOrigin = `http://127.0.0.1:${peer.address().port}`;
  try {
    // 대조군: redirect 옵션이 없는 평범한 fetch는 그대로 따라감 (이 테스트가 의미 있다는 증거)
    const followed = await fetch(peerOrigin + '/api/download/x', { headers: { 'x-transfer-token': 'secret' } });
    assert.equal(await followed.text(), 'leaked');
    assert.equal(wanHits.length, 1);
    wanHits.length = 0;

    const ctx = makeContext({ origin: peerOrigin, fetchImpl: fetch });
    await assert.rejects(ctx.peerFetch('/api/download/x', { headers: { 'x-transfer-token': 'secret' } }), isTypeError);
    await assert.rejects(ctx.peerFetch('/api/transfer', { method: 'POST', headers: { 'x-transfer-token': 'secret' }, body: 'file-bytes' }), isTypeError);
    assert.equal(wanHits.length, 0, 'no token or byte may reach the redirect target');
  } finally {
    wan.close();
    peer.close();
  }
}

/// 정적 검사: peer 요청은 전부 peerFetch를 거쳐야 함(새 요청이 규칙을 우회 못 하게)
function testNoRawNetworkCalls() {
  const files = fs.readdirSync(JS_DIR).filter((f) => f.endsWith('.js')).map((f) => path.join(JS_DIR, f));
  files.push(path.join(__dirname, '../assets/web/app.js'));
  let webSockets = 0;
  for (const file of files) {
    let src = fs.readFileSync(file, 'utf8');
    if (path.basename(file) === 'peer_address.js') {
      const start = src.indexOf('function peerFetch(');
      const end = src.indexOf('\n}\n', start) + 3;
      src = src.slice(0, start) + src.slice(end);
    }
    const code = src.replace(/\/\/.*$/gm, '');
    assert.ok(!/\bfetch\s*\(/.test(code), `${path.basename(file)}: raw fetch( outside peerFetch`);
    assert.ok(!/XMLHttpRequest/.test(code), `${path.basename(file)}: XMLHttpRequest cannot enforce redirect:"error"`);
    assert.ok(!/sendBeacon|EventSource/.test(code), `${path.basename(file)}: unexpected network API`);
    assert.ok(!/\b(?:localStorage|indexedDB|CacheStorage|caches|serviceWorker)\b/.test(code), `${path.basename(file)}: persistent browser storage is forbidden`);
    webSockets += (code.match(/new WebSocket\(/g) || []).length;
  }
  assert.equal(webSockets, 1, 'exactly one WebSocket construction site (socket.js connect)');
  assert.match(read('socket.js'), /new WebSocket\(wsUrl\)/);
  // 브라우저 상수는 Dart kProtocolVersion과 늘 같아야 함(hello 버전 게이트). 값을 여기 박지 않고
  // Dart 쪽에서 읽어서 버전을 올릴 때 같이 어긋나지 않게 함
  const dartVersion = /const String kProtocolVersion = '(\d+)';/.exec(
    fs.readFileSync(path.join(__dirname, '../lib/core/constants.dart'), 'utf8'),
  );
  assert.ok(dartVersion, 'kProtocolVersion not found in lib/core/constants.dart');
  assert.match(read('socket.js'), new RegExp(`var PROTOCOL_VERSION = "${dartVersion[1]}";`));
}

(async () => {
  const groups = [
    testEndpointParsing,
    testConnectAndUrls,
    testEntryAcceptance,
    testViewportFitKeepsFoldHeight,
    testGuestBurnTiming,
    testGuestFileQueue,
    testPeerFetchOptions,
    testRedirectNeverLeaves,
    testBrowserFileFlows,
    testDownloadStatusLocales,
    testStreamingDownloads,
    testDownloadEdgeCases,
    testVoiceResourceLifetime,
    testVoiceExpiryAcrossBfCache,
    testPagehideCancelsTransfers,
    testBfCacheReconnect,
    testBfCacheCycles,
    testDiscoverableReactionAndSlash,
    testReactionActivationCounts,
    testSlashShortcutGuards,
    testNoRawNetworkCalls,
  ];
  for (const group of groups) await group();
  console.log(`browser guard: PASS (${groups.length} test groups)`);
})().catch((e) => { console.error(e); process.exit(1); });
