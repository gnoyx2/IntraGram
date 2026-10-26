// 브라우저 언어를 기본으로 쓰고 헤더에서 고른 값은 RAM에만 둠 (게스트 설정 화면이나 영구 저장은 없음)
var langOverride = null;

function storedLang() {
  return langOverride;
}

function detectLang() {
  var stored = storedLang();
  if (stored === "ko" || stored === "en") return stored;
  return (navigator.language || "").toLowerCase().indexOf("ko") === 0 ? "ko" : "en";
}

var KO = detectLang() === "ko";

// 언어를 바꿀 때 새로고침 없이 문구를 다시 만들어서 RAM 대화를 지킴
function buildI18N() {
  return {
    guestTitle: KO ? "IntraGram 게스트" : "IntraGram Guest",
    connecting: KO ? "연결 중…" : "Connecting…",
    burn: KO ? "자동 삭제" : "Self-destruct",
    burnLeft: KO ? "{n}초" : "{n}s",
    burnsIn: KO ? "{n}초 뒤 사라져요" : "Disappears in {n} seconds",
    ttlOff: KO ? "끔" : "Off",
    ttlSeconds: KO ? "{n}초" : "{n}s",
    langAuto: KO ? "자동" : "Auto",
    logLabel: KO ? "메시지" : "Messages",
    like: KO ? "좋아요 토글" : "Toggle like",
    reactHint: KO ? "Enter를 누르거나 두 번 눌러 좋아요" : "Press Enter or double-click to like",
    langLabel: KO ? "언어" : "Language",
    sendFile: KO ? "파일 보내기" : "Send a file",
    message: KO ? "메시지" : "Message",
    send: KO ? "보내기" : "Send",
    plainNotice: KO
      ? "이 브라우저 대화는 Wi-Fi에서 암호화되지 않아요. 종단 간 암호화는 앱끼리 1:1 대화뿐이에요."
      : "This browser chat is not encrypted on the Wi-Fi. Only app-to-app 1:1 chats are end-to-end encrypted.",
    connectedAs: KO
      ? "{alias}(으)로 연결됐어요. 메시지는 메모리에만 있어요."
      : "Connected as {alias}. Messages live only in memory.",
    reconnecting: KO ? "연결 끊김, 다시 시도하는 중…" : "Disconnected, retrying…",
    reconnected: KO
      ? "다시 연결됐어요. 끊긴 동안 온 메시지는 받지 못했어요."
      : "Reconnected. Messages sent while you were away did not reach you.",
    joining: KO ? "들어가는 중…" : "Joining…",
    rejected: KO
      ? "포털이 꺼졌거나 입장 코드가 바뀌었어요. 앱의 게스트 포털에서 QR을 다시 스캔하세요."
      : "The guest portal is off or its entry code changed. Scan the QR code in the app's guest portal again.",
    roomFull: KO
      ? "방이 꽉 찼어요. 누가 나간 뒤 이 페이지를 새로고침하세요."
      : "The room is full. Reload this page once someone leaves.",
    roomCount: KO ? "호스트를 포함해 {n}명이 이 방에 있어요." : "{n} people are in this room, including the host.",
    memberJoined: KO ? "{alias}님이 들어왔어요 · {n}명" : "{alias} joined · {n} people",
    memberLeft: KO ? "{alias}님이 나갔어요 · {n}명" : "{alias} left · {n} people",
    online: KO ? "온라인" : "Online",
    typing: KO ? "입력 중…" : "Typing…",
    typingFrom: KO ? "{from}님이 입력 중…" : "{from} is typing…",
    fileTag: KO ? "파일" : "File",
    messageDeleted: KO ? "삭제된 메시지" : "Message deleted",
    fileDeclined: KO ? "상대가 파일을 거절했어요." : "The other side declined the file.",
    voiceMessage: KO ? "음성 메시지" : "Voice message",
    voiceExpired: KO ? "더 이상 재생할 수 없음" : "No longer available",
    download: KO ? "다운로드" : "Download",
    decline: KO ? "거절" : "Decline",
    downloading: KO ? "{name} 내려받는 중…" : "Downloading {name}…",
    downloadComplete: KO
      ? "{name} 받음. 브라우저 다운로드를 확인하세요"
      : "{name} received — check your browser's downloads",
    bigDownload: KO
      ? "큰 파일이에요. 브라우저가 메모리에 다 받은 뒤 저장해서 휴대폰에선 실패할 수 있어요."
      : "Large file. The browser holds all of it in memory before saving, which can fail on a phone.",
    filesHostOnly: KO
      ? "브라우저에서 보낸 파일은 호스트에게만 가고 다른 게스트에게는 가지 않아요."
      : "Files you send from the browser reach the host only, not other guests.",
    filesQueued: KO ? "파일 {n}개를 하나씩 보내요." : "Sending {n} files one at a time.",
    downloadFailed: KO ? "다운로드 실패" : "Download failed",
    uploading: KO ? "{name} 보내는 중…" : "Sending {name}…",
    waitingForPeer: KO
      ? "{name} · 상대 기다리는 중…"
      : "{name} — waiting for peer…",
    sent: KO ? "{name} 보냄" : "{name} sent",
    uploadFailed: KO ? "업로드 실패" : "Upload failed",
    cancel: KO ? "취소" : "Cancel",
    transferCancelled: KO ? "전송 취소됨" : "Transfer cancelled",
    sendFailed: KO ? "전송 실패" : "Failed to send",
    newMessages: KO ? "새 메시지 {n}개 ↓" : "{n} new messages ↓",
    today: KO ? "오늘" : "Today",
    yesterday: KO ? "어제" : "Yesterday",
    noToken: KO
      ? "입장 코드가 없는 주소예요. 앱의 게스트 포털에서 QR을 다시 스캔하거나 전체 주소(#t=… 포함)를 그대로 열어 주세요."
      : "This address has no entry code. Scan the QR code in the app's guest portal again, or open the full address including #t=….",
  };
}
var I18N = buildI18N();

function t(key, vars) {
  var s = I18N[key] || key;
  if (vars) {
    for (var k in vars) s = s.split("{" + k + "}").join(vars[k]);
  }
  return s;
}

function isKorean() {
  return KO;
}

function setLang(value) {
  langOverride = value;
  KO = detectLang() === "ko";
  I18N = buildI18N();
}
