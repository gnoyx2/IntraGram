var logEl = document.getElementById("log");
var attachEl = document.getElementById("attach");
var fileEl = document.getElementById("file-input");

// 파일 선택·드롭·붙여넣기는 여기로 모임. 여러 개면 줄을 세워 하나씩 제안함
// (앞 파일이 다 가거나 거절·취소되면 다음 것)
var activeUploads = {}; // 전송 ID별 취소용 AbortController
var activeDownloads = Object.create(null);
var pendingSend = null; // file_accept를 기다리는 {id, attempt, file}
var sendQueue = [];
var toldHostOnly = false;

// 브라우저는 파일을 다 받은 뒤 한 번에 저장해서 이보다 크면 미리 알림
var BIG_DOWNLOAD = 200 * 1000 * 1000;

// 앱과 같은 10진 단위(1 KB = 1000 B). 반올림해 1000이 되면 다음 단위로 올림
function formatBytes(n) {
  if (n < 1000) return n + " B";
  var u = ["KB", "MB", "GB", "TB"], i = -1;
  do { n /= 1000; i++; } while (n >= 999.5 && i < u.length - 1);
  return n.toFixed(n >= 100 ? 0 : 1) + " " + u[i];
}

function incomingOffer(inner) {
  // 브라우저는 서버가 아니라 POST를 못 받아서 pull이 아닌(push) offer는 처음부터 거절함 (v3부터 md는 늘 옴)
  if (inner.md !== "pull") {
    sendInner({ k: "file_reject", id: inner.id, at: inner.at });
    return;
  }
  if (inner.vc) {
    addBubble({ id: inner.id, mine: false, node: renderVoiceMessage(inner), file: true });
    return;
  }
  var wrap = document.createElement("div");
  wrap.className = "xfer-incoming";
  var label = document.createElement("div");
  label.className = "xfer-name";
  // 이모지 대신 첨부 버튼의 클립 SVG를 복제해 OS와 상관없이 같은 선 아이콘을 씀
  var clip = attachEl.querySelector("svg");
  if (clip) label.appendChild(clip.cloneNode(true));
  var name = document.createElement("span");
  name.textContent = inner.name + " (" + formatBytes(inner.size) + ")";
  label.appendChild(name);
  wrap.appendChild(label);
  if (inner.size > BIG_DOWNLOAD) {
    var big = document.createElement("div");
    big.className = "xfer-note";
    big.textContent = t("bigDownload");
    wrap.appendChild(big);
  }
  if (inner.th) {
    // 수락 전 미리보기 썸네일. data: URI라 <img> 안에선 실행 안 됨
    var thumb = document.createElement("img");
    thumb.src = "data:image/png;base64," + inner.th;
    thumb.alt = inner.name || t("fileTag");
    thumb.className = "xfer-thumb";
    wrap.appendChild(thumb);
  }
  var accept = document.createElement("button");
  accept.className = "btn btn-accent";
  accept.textContent = t("download");
  accept.setAttribute("aria-label", t("download") + ": " + inner.name);
  var decline = document.createElement("button");
  decline.className = "btn btn-ghost";
  decline.textContent = t("decline");
  decline.setAttribute("aria-label", t("decline") + ": " + inner.name);
  accept.onclick = function () {
    accept.disabled = true;
    decline.remove();
    label.textContent = t("downloading", { name: inner.name });
    // 토큰이 필요한 pull은 <a> 대신 peerFetch로 받음. URL은 사설 LAN이나 같은 출처만 허용함
    var downloadUrl = resolveDownloadUrl(inner.id, inner.sh, inner.sp);
    if (!downloadUrl) {
      label.textContent = t("downloadFailed");
      return;
    }
    var ctl = new AbortController();
    activeDownloads[inner.id] = ctl;
    var progress = document.createElement("div");
    progress.className = "xfer-progress";
    progress.setAttribute("role", "progressbar");
    progress.setAttribute("aria-label", t("downloading", { name: inner.name }));
    if (inner.size > 0) {
      progress.setAttribute("aria-valuemin", "0");
      progress.setAttribute("aria-valuemax", "100");
      progress.setAttribute("aria-valuenow", "0");
    }
    var cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "btn btn-ghost";
    cancel.textContent = t("cancel");
    cancel.setAttribute("aria-label", t("cancel") + ": " + inner.name);
    cancel.onclick = function () {
      ctl.abort();
      sendInner({ k: "file_cancel", id: inner.id, at: inner.at });
      label.textContent = t("transferCancelled");
      cancel.remove();
      progress.remove();
    };
    wrap.appendChild(progress);
    wrap.appendChild(cancel);
    peerFetch(downloadUrl, { headers: pullHeaders(inner), signal: ctl.signal })
      .then(function (res) {
        if (!res.ok) throw new Error("file download failed");
        return readDownload(res, inner.size, progress, ctl.signal);
      })
      .then(function (blob) {
        if (ctl.signal.aborted) return;
        if (typeof blob.size === "number" && blob.size !== inner.size) throw new Error("incomplete file");
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = inner.name;
        document.body.appendChild(a);
        a.click();
        a.remove();
        // 저장 창(특히 iOS)이 blob을 다 읽기 전에 URL을 없애면 조용히 저장이 안 됨: 40초 뒤에 해제
        setTimeout(function () { URL.revokeObjectURL(url); }, 40000);
        // wire EOF와 이 ACK가 모두 있어야 발신자가 완료로 침
        sendInner({ k: "file_received", id: inner.id, at: inner.at });
        accept.remove();
        label.textContent = t("downloadComplete", { name: inner.name });
      })
      .catch(function (err) {
        label.textContent = ctl.signal.aborted || (err && err.name === "AbortError")
          ? t("transferCancelled") : t("downloadFailed");
      })
      .finally(function () {
        if (activeDownloads[inner.id] === ctl) delete activeDownloads[inner.id];
        if (ctl.signal.aborted) accept.remove();
        cancel.remove();
        progress.remove();
      });
  };
  decline.onclick = function () {
    sendInner({ k: "file_reject", id: inner.id, at: inner.at });
    wrap.remove();
  };
  wrap.appendChild(accept);
  wrap.appendChild(decline);
  addBubble({ id: inner.id, mine: false, node: wrap, file: true });
}

// 스트림이 없는 브라우저·테스트는 blob 경로를 유지함. ACK는 이 함수가 EOF까지 끝난 뒤에만 보냄
async function readDownload(res, total, progress, signal) {
  if (!res.body || typeof res.body.getReader !== "function") return res.blob();
  var reader = res.body.getReader();
  var chunks = [], received = 0;
  var abort = function () { reader.cancel().catch(function () {}); };
  signal.addEventListener("abort", abort);
  try {
    while (!signal.aborted) {
      var part = await reader.read();
      if (part.done) break;
      chunks.push(part.value);
      received += part.value.byteLength;
      if (total > 0 && received > total) throw new Error("file size exceeded");
      progress.textContent = total > 0
        ? Math.min(100, Math.floor(received * 100 / total)) + "% · " + formatBytes(received)
        : formatBytes(received);
      if (total > 0) progress.setAttribute("aria-valuenow", Math.min(100, Math.floor(received * 100 / total)));
    }
    if (signal.aborted) return null;
    if (total >= 0 && received !== total) throw new Error("incomplete file");
    return new Blob(chunks);
  } finally {
    signal.removeEventListener("abort", abort);
    await reader.cancel().catch(function () {});
    reader.releaseLock();
    chunks.forEach(function (chunk) { chunk.fill(0); });
  }
}

// pull 다운로드 요청 헤더: offer가 준 토큰·attempt와 선언 크기 (서버가 슬롯을 쓰기 전에 셋 다 검증함)
function pullHeaders(inner) {
  return {
    "x-transfer-token": inner.tok,
    "x-transfer-attempt": inner.at,
    "x-file-size": String(inner.size),
  };
}

function pickFile() {
  if (!isReady()) return;
  fileEl.click();
}

function offerFiles(files) {
  var list = Array.prototype.slice.call(files || []).filter(Boolean);
  if (!isReady() || !list.length) return;
  if (!toldHostOnly) {
    // 웹 게스트 방은 파일을 중계하지 않음: 다른 게스트는 못 받음
    toldHostOnly = true;
    system(t("filesHostOnly"));
  }
  sendQueue = sendQueue.concat(list);
  if (sendQueue.length > 1) system(t("filesQueued", { n: sendQueue.length }));
  offerNext();
}

// 기다리는 제안도 올라가는 중인 파일도 없을 때 줄의 다음 파일을 제안함
function offerNext() {
  if (!isReady() || pendingSend || Object.keys(activeUploads).length || !sendQueue.length) return;
  offerFile(sendQueue.shift());
}

function offerFile(file) {
  if (!isReady() || !file || pendingSend) return;
  var id = newId();
  var attempt = newId();
  pendingSend = { id: id, attempt: attempt, file: file };
  sendInner({ k: "file_offer", id: id, at: attempt, md: "push", name: file.name, size: file.size });
  var wrap = document.createElement("div");
  wrap.className = "xfer";
  var label = document.createElement("span");
  label.className = "xfer-label";
  label.textContent = t("waitingForPeer", { name: file.name });
  wrap.appendChild(label);
  var cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "btn btn-ghost";
  cancel.textContent = t("cancel");
  cancel.setAttribute("aria-label", t("cancel") + ": " + file.name);
  cancel.onclick = function () {
    sendInner({ k: "file_cancel", id: id, at: attempt });
    var ctl = activeUploads[id];
    if (ctl) ctl.abort();
    delete activeUploads[id];
    if (pendingSend && pendingSend.id === id) pendingSend = null;
    wrap.textContent = t("transferCancelled");
    offerNext();
  };
  wrap.appendChild(cancel);
  addBubble({ id: id, mine: true, node: wrap, file: true });
}

// file_accept가 실어 온 토큰으로 POST함. XHR은 redirect를 못 막아서(3xx면 헤더·본문이 그대로 따라감) fetch를 씀.
// peerFetch가 redirect:'error'·no-store를 강제하고 목적지가 RFC1918이나 같은 출처인지도 봄.
// fetch는 업로드 진행률 이벤트가 없어서 % 대신 '보내는 중' 상태만 보임
function uploadFile(inner) {
  if (!pendingSend || pendingSend.id !== inner.id || pendingSend.attempt !== inner.at) return;
  var pkg = pendingSend;
  pendingSend = null;
  var wrapEl = logEl.querySelector('.bubble[data-id="' + cssEscape(pkg.id) + '"] .xfer');
  var bubble = wrapEl ? wrapEl.querySelector(".xfer-label") : null;
  function finish(text) {
    delete activeUploads[pkg.id];
    if (wrapEl) wrapEl.textContent = text;
    offerNext();
  }
  if (bubble) bubble.textContent = t("uploading", { name: pkg.file.name });
  var ctl = new AbortController();
  activeUploads[pkg.id] = ctl;
  peerFetch("/api/transfer", {
    method: "POST",
    signal: ctl.signal,
    headers: {
      "content-type": "application/octet-stream",
      "x-transfer-id": pkg.id,
      "x-transfer-attempt": pkg.attempt,
      "x-transfer-token": inner.tok,
      "x-file-name": btoa(unescape(encodeURIComponent(pkg.file.name))),
      "x-file-size": String(pkg.file.size),
    },
    body: pkg.file,
  })
    .then(function (res) {
      // 403은 상대가 거절한 결과라 업로드 실패 대신 거절 문구를 보여 줌
      finish(res.status === 200
        ? t("sent", { name: pkg.file.name })
        : res.status === 403 ? t("fileDeclined") : t("uploadFailed"));
    })
    .catch(function (err) {
      // 취소로 끊은 요청은 이미 '전송 취소됨'을 띄웠으니 '업로드 실패'로 덮지 않음
      finish(err && err.name === "AbortError" ? t("transferCancelled") : t("uploadFailed"));
    });
}

// app.js에서 넘긴 파일 프레임 처리
function handleFileOffer(inner) { incomingOffer(inner); }
function handleFileAccept(inner) { uploadFile(inner); }
function handleFileReject(inner) {
  if (pendingSend && pendingSend.id === inner.id && pendingSend.attempt === inner.at) {
    system(t("fileDeclined"));
    pendingSend = null;
    offerNext();
  }
}
function handleFileCancel(id) {
  // 상대가 보내려던 걸 거둬들였을 때: 수락 전이면 offer 자리를, 받는 중이면 그 상태 표시를 취소 문구로 바꿈
  var incomingWrap = logEl.querySelector('.bubble[data-id="' + cssEscape(id) + '"] .xfer-incoming');
  if (activeDownloads[id]) activeDownloads[id].abort();
  releaseVoice(id);
  if (incomingWrap) incomingWrap.textContent = t("transferCancelled");
}

function applyFileLocale() {
  attachEl.title = t("sendFile");
  attachEl.setAttribute("aria-label", t("sendFile"));
}

function initFileTransfer() {
  window.addEventListener("pagehide", function () {
    sendQueue = [];
    if (pendingSend) {
      var pending = logEl.querySelector('.bubble[data-id="' + cssEscape(pendingSend.id) + '"] .xfer');
      if (pending) pending.textContent = t("transferCancelled");
      pendingSend = null;
    }
    Object.keys(activeDownloads).forEach(function (id) { activeDownloads[id].abort(); });
    Object.keys(activeUploads).forEach(function (id) { activeUploads[id].abort(); });
  });
  attachEl.onclick = pickFile;

  fileEl.onchange = function () {
    var files = Array.prototype.slice.call(fileEl.files || []);
    fileEl.value = "";
    offerFiles(files);
  };

  function dragHasFiles(e) {
    var types = (e.dataTransfer && e.dataTransfer.types) || [];
    return Array.prototype.indexOf.call(types, "Files") !== -1;
  }
  var dragDepth = 0;
  window.addEventListener("dragenter", function (e) {
    if (!dragHasFiles(e)) return;
    dragDepth++;
    document.body.classList.add("drag-over");
  });
  window.addEventListener("dragover", function (e) {
    // dragover마다 기본 동작을 막아야 drop이 들어옴
    if (dragHasFiles(e)) e.preventDefault();
  });
  window.addEventListener("dragleave", function (e) {
    if (!dragHasFiles(e)) return;
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) document.body.classList.remove("drag-over");
  });
  window.addEventListener("drop", function (e) {
    dragDepth = 0;
    document.body.classList.remove("drag-over");
    if (!dragHasFiles(e)) return;
    e.preventDefault();
    offerFiles(e.dataTransfer.files);
  });
  document.addEventListener("paste", function (e) {
    var files = e.clipboardData && e.clipboardData.files;
    // 파일이 없으면 일반 텍스트 붙여넣기를 그대로 둠
    if (!files || !files.length) return;
    e.preventDefault();
    offerFiles(files);
  });
}
