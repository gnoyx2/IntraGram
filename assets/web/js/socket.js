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
var reconnectTimer = null;
var connectionCallbacks = null;
var suspended = false;
var retryAllowed = true;

function suspendConnection() {
  suspended = true;
  ready = false;
  clearTimeout(reconnectTimer);
  reconnectTimer = null;
  if (connectionCallbacks) connectionCallbacks.onClose();
  if (ws) ws.close();
  ws = null;
}
window.addEventListener("pagehide", suspendConnection);
window.addEventListener("pageshow", function (event) {
  if (!event.persisted || !connectionCallbacks || !retryAllowed) return;
  suspendConnection();
  suspended = false;
  reconnectAttempts = 0;
  setStatus(t("reconnecting"), false);
  connect(connectionCallbacks.onFrame, connectionCallbacks.onOpen, connectionCallbacks.onClose);
});
// 호스트가 이번 페이지에서 한 번이라도 받아 줬는지 여부 (이후 입장은 재연결로 처리함)
var everAccepted = false;
var reconnectAttempts = 0;
var RECONNECT_BASE_MS = 1000;
var RECONNECT_MAX_MS = 15000;

// lib/core/constants.dart의 kProtocolVersion과 같이 올려야 함
var PROTOCOL_VERSION = "7";

// QR·URL 조각(#t=...)의 포털 토큰은 한 번 읽고 주소창에서 지움 (브라우저 기록에도 안 남게).
// 새로고침·탭 복원에도 다시 들어오게 이 탭의 sessionStorage에만 둠 (탭을 닫으면 사라짐). 호스트가 안 받아 주면(포털 끔, 새 코드) 지움
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

// 평문 프레임과 연결 상태를 콜백으로 넘김 (채팅·파일 UI 연결은 app.js 몫)
function connect(onFrame, onOpen, onClose) {
  connectionCallbacks = { onFrame: onFrame, onOpen: onOpen, onClose: onClose };
  if (suspended) return;
  clearTimeout(reconnectTimer);
  reconnectTimer = null;
  // 입장 토큰 없이는 서버가 web_hello를 거절하고 끊으므로 재시도하지 않고 이유를 보여 줌
  // (주소를 직접 입력했거나 토큰 없이 새 탭에서 열어 #t=가 없는 경우)
  if (!TOKEN) {
    setStatus(t("noToken"), false);
    system(t("noToken"));
    return;
  }
  var wsUrl = (location.protocol === "https:" ? "wss:" : "ws:") + "//" + location.host + "/ws";
  var socket = new WebSocket(wsUrl);
  ws = socket;
  // 소켓이 열린 것과 호스트가 입장 코드를 받아 준 것(첫 프레임, 지금 인원)은 다름:
  // '온라인'과 재시도 간격 초기화는 받아 준 뒤에만 함
  var opened = false;
  var accepted = false;
  var roomFull = false;

  socket.onopen = function () {
    if (ws !== socket || suspended) return;
    opened = true;
    send({ t: "web_hello", v: PROTOCOL_VERSION, alias: ALIAS, tok: TOKEN });
    setStatus(t("joining"), false);
  };
  socket.onclose = function () {
    if (ws !== socket || suspended) return;
    ready = false;
    onClose();
    if (roomFull) return;
    if (opened && !accepted) {
      // 열렸는데 받아 주지 않고 닫힘 = 포털이 꺼졌거나 입장 코드가 바뀜. 계속 두드리지 않고 이유를 보여 줌
      rememberToken(null);
      TOKEN = null;
      retryAllowed = false;
      setStatus(t("rejected"), false);
      system(t("rejected"));
      return;
    }
    setStatus(t("reconnecting"), false);
    var delay = Math.min(RECONNECT_MAX_MS, RECONNECT_BASE_MS * Math.pow(1.6, reconnectAttempts));
    reconnectAttempts++;
    // 재연결에도 같은 콜백을 넘겨서 UI 상태 갱신이 이어짐
    reconnectTimer = setTimeout(function () { connect(onFrame, onOpen, onClose); }, delay);
  };
  socket.onerror = function () { try { socket.close(); } catch (e) {} };
  socket.onmessage = function (ev) {
    if (ws !== socket || suspended) return;
    var frame;
    try { frame = JSON.parse(ev.data); } catch (e) { return; }
    if (frame.t !== "plain" || !frame.d) return;
    if (frame.d.k === "room_full") {
      // 게스트 수 상한: 받아 주지 않은 것과 같게 재시도 없이 이유만 보여 줌
      roomFull = true;
      retryAllowed = false;
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
