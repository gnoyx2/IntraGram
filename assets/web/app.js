// 서버가 js/*.js를 의존 순서대로 이어 붙이는 진입점. 전역 스코프를 공유해 추가 요청 없이 한 문서로 내려줌.

var langEl = document.getElementById("lang");

function handleInner(inner) {
  switch (inner.k) {
    case "msg": handleMsg(inner); break;
    case "read": handleRead(inner.id); break;
    case "burn": handleBurn(inner.id); break;
    case "react": handleReact(inner); break;
    case "typing": handleTyping(inner); break;
    case "file_offer": handleFileOffer(inner); break;
    case "file_accept": handleFileAccept(inner); break;
    case "file_reject": handleFileReject(inner); break;
    case "file_cancel": handleFileCancel(inner.id); break;
    case "room_state": handleRoomState(inner); break;
  }
}

function onOpen(isReconnect) {
  setSendEnabled(true);
  system(isReconnect ? t("reconnected") : t("connectedAs", { alias: ALIAS }));
}
function onClose() {
  setSendEnabled(false);
}

function applyLocale() {
  document.documentElement.lang = isKorean() ? "ko" : "en";
  document.title = t("guestTitle");
  langEl.setAttribute("aria-label", t("langLabel"));
  document.getElementById("plain-notice").textContent = t("plainNotice");
  applyChatLocale();
  applyFileLocale();
}

initChatUi();
initFileTransfer();
applyLocale();
langEl.value = storedLang() || "auto";
langEl.onchange = function () {
  // 새로고침하면 RAM 대화가 사라지므로 문구만 다시 그림.
  setLang(langEl.value);
  applyLocale();
};

connect(handleInner, onOpen, onClose);
