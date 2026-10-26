// 메시지 생명주기와 fetch·audio·blob URL을 함께 끝냄 (BFCache에도 음성 바이트를 남기지 않음)
var voiceResources = Object.create(null);
function releaseVoice(id) {
  var resource = voiceResources[id];
  if (!resource) return;
  delete voiceResources[id];
  resource.ctl.abort();
  resource.audio.pause();
  resource.audio.removeAttribute("src");
  resource.audio.load();
  // 회수한 플레이어를 재생할 수 있는 것처럼 남기지 않음. BFCache 복귀 뒤에도 다시 받지 않고 안내만 남김
  resource.audio.remove();
  resource.label.textContent = t("voiceMessage") + " · " + t("voiceExpired");
  if (resource.url) URL.revokeObjectURL(resource.url);
}
window.addEventListener("pagehide", function () {
  Object.keys(voiceResources).forEach(releaseVoice);
});

// 음성 메시지는 폴더도 다운로드 버튼도 없이 바로 재생함 (게스트는 이미 LAN 평문임)
function renderVoiceMessage(inner) {
  var wrap = document.createElement("div");
  wrap.className = "xfer-incoming";
  var label = document.createElement("div");
  label.textContent = t("voiceMessage");
  wrap.appendChild(label);
  var audio = document.createElement("audio");
  audio.controls = true;
  audio.setAttribute("aria-label", t("voiceMessage"));
  audio.className = "xfer-audio";
  wrap.appendChild(audio);
  // pull 다운로드는 토큰이 필요한데 <audio src>는 커스텀 헤더를 못 실어서 fetch로 받아 blob URL을 붙임
  // (inner.tok는 offer를 낸 쪽이 발급한 값)
  var downloadUrl = resolveDownloadUrl(inner.id, inner.sh, inner.sp);
  if (!downloadUrl) {
    label.textContent = t("voiceMessage") + " · " + t("downloadFailed");
    return wrap;
  }
  releaseVoice(inner.id);
  var resource = { audio: audio, label: label, ctl: new AbortController(), url: null };
  voiceResources[inner.id] = resource;
  peerFetch(downloadUrl, { headers: pullHeaders(inner), signal: resource.ctl.signal })
    .then(function (res) {
      if (!res.ok) throw new Error("voice download failed");
      return res.blob();
    })
    .then(function (blob) {
      // blob 타입은 보낸 쪽 서버가 정함. 재생목록 MIME이면 Safari가 HLS로 읽을 수 있어서 녹음기 형식(WAV)으로 고정함
      if (voiceResources[inner.id] !== resource) return;
      resource.url = URL.createObjectURL(new Blob([blob], { type: "audio/wav" }));
      audio.src = resource.url;
      // 끝까지 받았다고 보내는 쪽에 알림 (보내는 쪽은 wire EOF와 이 ACK가 둘 다 있어야 완료)
      sendInner({ k: "file_received", id: inner.id, at: inner.at });
    })
    .catch(function () {
      if (resource.ctl.signal.aborted) return;
      label.textContent = t("voiceMessage") + " · " + t("downloadFailed");
    });
  return wrap;
}
