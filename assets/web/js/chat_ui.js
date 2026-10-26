var logEl = document.getElementById("log");
var inputEl = document.getElementById("input");
var sendEl = document.getElementById("send");
var ttlEl = document.getElementById("ttl");
var jumpEl = document.getElementById("jump-latest");

// 언어 관례를 따름: 한국어는 '오후 3:04', 영어는 브라우저 지역 설정의 12/24시간
function clock() {
  return new Date().toLocaleTimeString(isKorean() ? "ko-KR" : [], { hour: "numeric", minute: "2-digit" });
}

// 스크린 리더에만 바로 읽히는 알림 (전송 실패처럼 화면 표시만으론 놓치는 상태)
var srAlertEl = document.getElementById("sr-alert");
function announce(text) {
  if (!srAlertEl) return;
  srAlertEl.textContent = "";
  srAlertEl.textContent = text;
}

function atBottom() {
  return logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight < 60;
}
function scroll() { logEl.scrollTop = logEl.scrollHeight; }

function system(text) {
  var el = document.createElement("div");
  el.className = "system";
  el.textContent = text;
  logEl.appendChild(el);
  scroll();
}

// 날짜 구분선
var lastDateKey = null;
function dateKey(ms) {
  var d = new Date(ms);
  return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate();
}
function formatDateSep(ms) {
  var d = new Date(ms), now = new Date();
  if (dateKey(ms) === dateKey(now.getTime())) return t("today");
  var y = new Date(now);
  y.setDate(y.getDate() - 1);
  if (dateKey(ms) === dateKey(y.getTime())) return t("yesterday");
  return d.toLocaleDateString(isKorean() ? "ko-KR" : "en-US", {
    month: "long",
    day: "numeric",
    year: d.getFullYear() !== now.getFullYear() ? "numeric" : undefined,
  });
}
function maybeInsertDateSep(ms) {
  var key = dateKey(ms);
  if (key === lastDateKey) return;
  lastDateKey = key;
  var el = document.createElement("div");
  el.className = "date-sep";
  el.textContent = formatDateSep(ms);
  logEl.appendChild(el);
}

// 안 읽음 표시와 최신으로 이동
var unread = 0;
function updateJump() {
  if (unread > 0) {
    jumpEl.hidden = false;
    jumpEl.textContent = t("newMessages", { n: unread });
  } else {
    jumpEl.hidden = true;
  }
}

// 메시지 그리기
var LINK_RE = /https?:\/\/[^\s<>()\[\]]+/gi;
function linkifyInto(el, text) {
  LINK_RE.lastIndex = 0;
  var last = 0, m;
  while ((m = LINK_RE.exec(text)) !== null) {
    if (m.index > last) {
      el.appendChild(document.createTextNode(text.slice(last, m.index)));
    }
    var a = document.createElement("a");
    a.href = m[0];
    a.textContent = m[0];
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    el.appendChild(a);
    last = m.index + m[0].length;
  }
  if (last < text.length) {
    el.appendChild(document.createTextNode(text.slice(last)));
  }
}

function addBubble(opts) {
  maybeInsertDateSep(opts.ts || Date.now());
  var stick = atBottom();
  var row = document.createElement("div");
  row.className = "row " + (opts.mine ? "mine" : "theirs");
  var bubble = document.createElement("div");
  bubble.className = "bubble" + (opts.file ? " file" : "");
  bubble.dataset.id = opts.id;

  if (opts.from && !opts.mine) {
    var sender = document.createElement("div");
    sender.className = "sender";
    sender.textContent = opts.from;
    bubble.appendChild(sender);
  }

  if (opts.re) {
    var q = document.createElement("div");
    q.className = "quote";
    var parent = logEl.querySelector('.bubble[data-id="' + cssEscape(opts.re) + '"]');
    q.textContent = parent ? (parent.dataset.text || t("fileTag")) : t("messageDeleted");
    bubble.appendChild(q);
  }

  var body = document.createElement("div");
  if (opts.node) { body.appendChild(opts.node); } else { linkifyInto(body, opts.text || ""); }
  bubble.appendChild(body);
  if (opts.text) bubble.dataset.text = opts.text;

  var meta = document.createElement("div");
  meta.className = "meta";
  // 카운트다운·읽음·시각을 갱신할 때 aria-live가 같은 줄을 또 읽지 않게 함 (새 메시지 본문은 별도 노드라 그대로 읽힘)
  meta.setAttribute("aria-hidden", "true");
  var burnSpan = document.createElement("span");
  burnSpan.className = "burn";
  meta.appendChild(burnSpan);
  var stateSpan = document.createElement("span");
  stateSpan.className = "state";
  meta.appendChild(stateSpan);
  var time = document.createElement("span");
  time.textContent = clock();
  meta.appendChild(time);
  bubble.appendChild(meta);

  var reax = document.createElement("div");
  reax.className = "reactions";
  bubble.appendChild(reax);

  // 상대 말풍선은 두 번 누르거나, 키보드로 와서 Enter·Space를 누르면 좋아요를 토글함
  if (!opts.mine) {
    var toggleLike = function () {
      var mine = reactionState[opts.id] && reactionState[opts.id][ALIAS] === "👍";
      var on = !mine;
      sendInner({ k: "react", id: opts.id, emoji: "👍", on: on });
      applyReaction(opts.id, ALIAS, "👍", on);
    };
    var action = document.createElement("button");
    action.type = "button";
    action.className = "btn reaction-action";
    action.textContent = "👍";
    action.setAttribute("aria-label", t("like"));
    action.setAttribute("aria-pressed", "false");
    // 더블클릭의 두 번째 click(detail 2)과 Enter를 누르고 있을 때의 반복 keydown은 한 번 누른 것으로 침.
    // 키보드로 누른 click은 detail이 0이라 그대로 토글됨
    action.onclick = function (e) { if (!e || e.detail <= 1) toggleLike(); };
    action.addEventListener("keydown", function (e) {
      if (e.repeat && (e.key === "Enter" || e.key === " ")) e.preventDefault();
    });
    action.addEventListener("dblclick", function (e) { e.stopPropagation(); });
    bubble.tabIndex = 0;
    bubble.title = t("reactHint");
    bubble.setAttribute("aria-description", t("reactHint"));
    bubble.addEventListener("dblclick", toggleLike);
    bubble.addEventListener("keydown", function (e) {
      if (e.target !== bubble || (e.key !== "Enter" && e.key !== " ")) return;
      e.preventDefault();
      if (!e.repeat) toggleLike();
    });
  }

  row.appendChild(bubble);
  if (action) row.appendChild(action);
  logEl.appendChild(row);
  if (stick) {
    scroll();
  } else if (!opts.mine) {
    unread++;
    updateJump();
  }

  // 카운트다운은 앱과 같이 '읽은 뒤'부터 시작함: 내 글은 상대 읽음이 올 때, 받은 글은 내가 볼 때 beginBurn을 호출함
  if (opts.ttl > 0) pendingBurns[opts.id] = { ttl: opts.ttl, span: burnSpan, body: body };
  return bubble;
}

var pendingBurns = {}; // 메시지 ID -> 아직 안 시작한 카운트다운

function beginBurn(id) {
  var burn = pendingBurns[id];
  if (!burn) return;
  delete pendingBurns[id];
  // 화면의 초 표시는 aria-hidden 줄이라, 시작할 때 한 번만 스크린 리더용 문장을 붙임
  var hint = document.createElement("span");
  hint.className = "sr-only";
  hint.textContent = " " + t("burnsIn", { n: burn.ttl });
  burn.body.appendChild(hint);
  startBurn(id, burn.ttl, burn.span);
}

// 진동을 지원 안 하는 브라우저면 조용히 건너뜀
function vibrate(pattern) {
  try { if (navigator.vibrate) navigator.vibrate(pattern); } catch (e) {}
}

function markSendState(bubble, ok) {
  if (ok) return;
  vibrate(30);
  var span = bubble.querySelector(".meta .state");
  if (span) { span.textContent = t("sendFailed"); span.className = "state failed"; }
  announce(t("sendFailed"));
}

var reactionState = {}; // 메시지 ID별 발신자 반응

function applyReaction(id, from, emoji, on) {
  var bubble = logEl.querySelector('.bubble[data-id="' + cssEscape(id) + '"]');
  if (!bubble) return;
  var state = reactionState[id] || (reactionState[id] = {});
  if (on) { state[from] = emoji; }
  else if (state[from] === emoji) { delete state[from]; }
  var counts = {};
  Object.keys(state).forEach(function (k) { counts[state[k]] = (counts[state[k]] || 0) + 1; });
  var action = bubble.parentNode.querySelector(".reaction-action");
  if (action) action.setAttribute("aria-pressed", String(state[ALIAS] === "👍"));
  var box = bubble.querySelector(".reactions");
  box.textContent = "";
  Object.keys(counts).forEach(function (e) {
    var chip = document.createElement("span");
    chip.textContent = e + " " + counts[e];
    box.appendChild(chip);
  });
}

var timers = {}; // 메시지 ID별 소각 타이머 ID
function startBurn(id, ttl, span) {
  var deadline = Date.now() + ttl * 1000;
  function tick() {
    var left = Math.round((deadline - Date.now()) / 1000);
    if (left <= 0) {
      clearInterval(timers[id]);
      delete timers[id];
      removeBubble(id);
      return;
    }
    span.textContent = t("burnLeft", { n: left });
  }
  timers[id] = setInterval(tick, 1000);
  tick();
}

function cssEscape(s) { return String(s).replace(/["\\]/g, "\\$&"); }

function markRead(id) {
  var b = logEl.querySelector('.bubble[data-id="' + cssEscape(id) + '"] .meta span:last-child');
  if (b && b.textContent.indexOf("\u2713") === -1) b.textContent += " \u2713\u2713";
}
function removeBubble(id) {
  releaseVoice(id);
  delete pendingBurns[id];
  if (timers[id]) { clearInterval(timers[id]); delete timers[id]; }
  delete reactionState[id];
  var b = logEl.querySelector('.bubble[data-id="' + cssEscape(id) + '"]');
  if (b) b.parentNode.remove();
}
