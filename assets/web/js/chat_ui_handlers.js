// ---- inbound frame handlers (routed here from app.js) ----------------
function handleMsg(inner) {
  vibrate(15);
  countHiddenUnread();
  addBubble({ id: inner.id, mine: false, from: inner.from, text: inner.text, ttl: inner.ttl || 0, re: inner.re, ts: inner.ts });
  // 탭이 뒤에 있으면 읽음·카운트다운을 탭이 보일 때로 미룸 (안 보는 사이 5초 메시지가 타 버리지 않게)
  if (document.hidden) unseen.push(inner.id);
  else seen(inner.id);
}
var unseen = [];
function seen(id) {
  sendInner({ k: "read", id: id });
  beginBurn(id);
}
function flushUnseen() {
  if (document.hidden) return;
  var ids = unseen;
  unseen = [];
  ids.forEach(seen);
}
// 내 글은 상대가 읽었다고 알려 올 때 카운트다운 시작 (앱과 같은 기준)
function handleRead(id) {
  markRead(id);
  beginBurn(id);
}
function handleBurn(id) { removeBubble(id); }
function handleReact(inner) { applyReaction(inner.id, inner.from || "peer", inner.emoji, inner.on); }
// 방 인원 변화. 입장 직후 첫 프레임(들어온 사람·나간 사람 없음)은 지금 인원만 알려 줌
function handleRoomState(inner) {
  var n = inner.count || 0;
  if (inner.joined) system(t("memberJoined", { alias: inner.joined, n: n }));
  else if (inner.left) system(t("memberLeft", { alias: inner.left, n: n }));
  else system(t("roomCount", { n: n }));
}

// 탭이 뒤에 있는 동안 온 메시지 수를 탭 제목에 띄움 (http 사설 주소라 알림 API는 못 씀)
var hiddenUnread = 0;
function countHiddenUnread() {
  if (!document.hidden) return;
  hiddenUnread++;
  document.title = "(" + hiddenUnread + ") " + t("guestTitle");
}
function clearHiddenUnread() {
  if (document.hidden || hiddenUnread === 0) return;
  hiddenUnread = 0;
  document.title = t("guestTitle");
}

function handleTyping(inner) {
  setStatus(inner.on ? (inner.from ? t("typingFrom", { from: inner.from }) : t("typing")) : t("online"), true);
}

// iOS Safari는 키보드가 떠도 레이아웃 높이를 안 줄여서 헤더가 밀려 사라짐: 보이는 높이에 몸통을 맞춤
// (Chrome은 viewport의 interactive-widget=resizes-content로 처리). 확대 중이면 건드리지 않음
function fitToVisibleViewport() {
  var vv = window.visualViewport;
  if (!vv) return;
  var fit = function () {
    document.body.style.height = vv.scale > 1.01 ? "" : vv.height + "px";
  };
  vv.addEventListener("resize", fit);
}

// ---- compose & send ---------------------------------------------
function sendText() {
  var text = inputEl.value.trim();
  if (!text || !isReady()) return;
  var id = newId();
  var ttl = parseInt(ttlEl.value, 10) || 0;
  var ts = Date.now();
  var bubble = addBubble({ id: id, mine: true, text: text, ttl: ttl, ts: ts });
  var ok = sendInner({ k: "msg", id: id, text: text, ttl: ttl, ts: ts });
  markSendState(bubble, ok);
  inputEl.value = "";
  inputEl.style.height = "auto";
  sendInner({ k: "typing", on: false });
}

function setSendEnabled(enabled) {
  sendEl.disabled = !enabled;
}

function applyChatLocale() {
  document.getElementById("lbl-burn").textContent = t("burn");
  for (var i = 0; i < ttlEl.options.length; i++) {
    var n = parseInt(ttlEl.options[i].value, 10);
    ttlEl.options[i].textContent = n ? t("ttlSeconds", { n: n }) : t("ttlOff");
  }
  document.querySelector('#lang option[value="auto"]').textContent = t("langAuto");
  logEl.setAttribute("aria-label", t("logLabel"));
  inputEl.setAttribute("aria-label", t("message"));
  inputEl.placeholder = t("message");
  sendEl.title = t("send");
  sendEl.setAttribute("aria-label", t("send"));
  setStatus(isReady() ? t("online") : t("reconnecting"), isReady());
  updateJump();
}

function initChatUi() {
  sendEl.onclick = sendText;
  sendEl.disabled = true;
  // 보내기를 눌러도 입력창 초점을 안 뺏음: Android에서 키보드가 매번 닫히지 않게
  sendEl.addEventListener("mousedown", function (e) { e.preventDefault(); });
  fitToVisibleViewport();
  document.addEventListener("visibilitychange", function () {
    clearHiddenUnread();
    flushUnseen();
  });

  jumpEl.onclick = function () {
    unread = 0;
    updateJump();
    // 직접 누른 이동만 부드럽게 스크롤함. 새 메시지 자동 이동에는 애니메이션을 안 씀.
    var reduceMotion = window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduceMotion) {
      scroll();
    } else {
      logEl.scrollTo({ top: logEl.scrollHeight, behavior: "smooth" });
    }
  };
  logEl.addEventListener("scroll", function () {
    if (unread > 0 && atBottom()) { unread = 0; updateJump(); }
  });

  var typingSent = false;
  inputEl.addEventListener("input", function () {
    inputEl.style.height = "auto";
    inputEl.style.height = Math.min(inputEl.scrollHeight, 120) + "px";
    var has = inputEl.value.trim().length > 0;
    if (has !== typingSent) { typingSent = has; sendInner({ k: "typing", on: has }); }
  });
  inputEl.addEventListener("keydown", function (e) {
    // IME 조합 중 Enter는 글자 확정용이라 메시지를 보내면 안 됨.
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing && e.keyCode !== 229) {
      e.preventDefault();
      sendText();
    }
  });
}
