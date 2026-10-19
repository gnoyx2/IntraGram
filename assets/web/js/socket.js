// 호스트 앱이 직접 내려주는 페이지라 모든 요청은 같은 출처로 감. 다른 곳에 올린 페이지는 지원 안 함
// (서버가 교차 출처 접근과 다른 출처의 WebSocket을 거부함).

// 게스트 신원
var ANIMALS = ["otter", "raven", "lynx", "heron", "ibex", "wren", "fox", "owl", "seal", "hare", "crow", "bat"];
var ADJ = ["blue", "calm", "swift", "quiet", "bright", "bold", "warm", "keen", "lucky", "brave", "cool", "kind"];
function rnd(a) { return a[Math.floor(Math.random() * a.length)]; }
var ALIAS = rnd(ADJ) + "-" + rnd(ANIMALS) + "-" + (10 + Math.floor(Math.random() * 89));

var msgSeq = 0;
function newId() {
  return Date.now().toString(16) + "-" + (msgSeq++).toString(16) + "-" + Math.floor(Math.random() * 1e6).toString(16);
}

var statusEl = document.getElementById("status");
function setStatus(text, on) {
  statusEl.textContent = text;
  statusEl.className = "status" + (on ? " on" : "");
}
statusEl.textContent = t("connecting");

var ws = null;
var ready = false;
// 호스트가 이번 페이지에서 한 번이라도 받아 줬는지 (다음 입장은 '다시 연결됨')
var everAccepted = false;
var reconnectAttempts = 0;
var RECONNECT_BASE_MS = 1000;
var RECONNECT_MAX_MS = 15000;

// lib/core/constants.dart의 kProtocolVersion과 함께 올려야 함.
var PROTOCOL_VERSION = "7";

// QR/URL 조각(#t=...)의 포털 토큰은 한 번 읽고 주소창에서 지움. 브라우저 기록 노출도 막음.
// 새로고침·탭 복원에도 다시 들어오게 이 탭의 sessionStorage에만 둠(탭을 닫으면 사라짐).
// 호스트가 받아 주지 않으면(포털 끔·새 코드) 지움
var TOKEN_KEY = "intragram-entry";
function rememberToken(value) {
  try {
    if (value) sessionStorage.setItem(TOKEN_KEY, value);
    else sessionStorage.removeItem(TOKEN_KEY);
  } catch (e) {}
}
var TOKEN = (function () {
  var match = /(?:^|[#&])t=([^&]+)/.exec(location.hash);
  if (!match) {
    try { return sessionStorage.getItem(TOKEN_KEY); } catch (e) { return null; }
  }
  history.replaceState(null, "", location.pathname + location.search);
  var token = decodeURIComponent(match[1]);
  rememberToken(token);
  return token;
})();

function isReady() {
  return ready;
}

function send(obj) {
  if (ws && ws.readyState === 1) { ws.send(JSON.stringify(obj)); return true; }
  return false;
}
function sendInner(inner) { return send({ t: "plain", d: inner }); }

// 평문 프레임과 연결 상태를 콜백으로 넘김. 채팅/파일 UI 연결은 app.js가 맡음.
function connect(onFrame, onOpen, onClose) {
  // 입장 토큰 없이는 서버가 web_hello를 거절하고 끊으므로 재시도하지 않고 이유를 보여 줌
  // (주소를 손으로 치거나 새로고침해서 #t=…가 빠진 경우)
  if (!TOKEN) {
    setStatus(t("noToken"), false);
    system(t("noToken"));
    return;
  }
  var wsUrl = (location.protocol === "https:" ? "wss:" : "ws:") + "//" + location.host + "/ws";
  ws = new WebSocket(wsUrl);
  // 소켓이 열린 것과 호스트가 입장 코드를 받아 준 것(첫 프레임, 지금 인원)은 다름:
  // '온라인'과 재시도 간격 초기화는 받아 준 뒤에만 함
  var opened = false;
  var accepted = false;
  var roomFull = false;

  ws.onopen = function () {
    opened = true;
    send({ t: "web_hello", v: PROTOCOL_VERSION, alias: ALIAS, tok: TOKEN });
    setStatus(t("joining"), false);
  };
  ws.onclose = function () {
    ready = false;
    onClose();
    if (roomFull) return;
    if (opened && !accepted) {
      // 열렸는데 받아 주지 않고 닫힘 = 포털이 꺼졌거나 입장 코드가 바뀜. 계속 두드리지 않고 이유를 보여 줌
      rememberToken(null);
      setStatus(t("rejected"), false);
      system(t("rejected"));
      return;
    }
    setStatus(t("reconnecting"), false);
    var delay = Math.min(RECONNECT_MAX_MS, RECONNECT_BASE_MS * Math.pow(1.6, reconnectAttempts));
    reconnectAttempts++;
    // 재연결에도 같은 콜백을 넘겨 UI 상태 갱신을 이어감.
    setTimeout(function () { connect(onFrame, onOpen, onClose); }, delay);
  };
  ws.onerror = function () { try { ws.close(); } catch (e) {} };
  ws.onmessage = function (ev) {
    var frame;
    try { frame = JSON.parse(ev.data); } catch (e) { return; }
    if (frame.t !== "plain" || !frame.d) return;
    if (frame.d.k === "room_full") {
      // 게스트 수 상한: 받아 주지 않은 것과 같게 재시도 없이 이유만 보여 줌
      roomFull = true;
      setStatus(t("roomFull"), false);
      system(t("roomFull"));
      return;
    }
    if (!accepted) {
      accepted = true;
      reconnectAttempts = 0;
      ready = true;
      setStatus(t("online"), true);
      onOpen(everAccepted);
      everAccepted = true;
    }
    onFrame(frame.d);
  };
}
