// 음성 메시지: 폴더도 다운로드 버튼도 없이 바로 재생 (게스트는 이미 LAN 평문).
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
  // pull 다운로드는 토큰이 필요함 — <audio src>는 커스텀 헤더를 못 실어서
  // fetch로 받아 blob URL을 붙임. inner.tok는 offer를 낸 쪽이 발급한 값.
  var downloadUrl = resolveDownloadUrl(inner.id, inner.sh, inner.sp);
  if (!downloadUrl) {
    label.textContent = t("voiceMessage") + " — " + t("downloadFailed");
    return wrap;
  }
  peerFetch(downloadUrl, { headers: pullHeaders(inner) })
    .then(function (res) {
      if (!res.ok) throw new Error("voice download failed");
      return res.blob();
    })
    .then(function (blob) {
      // blob 타입은 보낸 쪽 서버가 정함. 재생목록 MIME이면 Safari가 HLS로 읽을 수 있어
      // 녹음기 형식(WAV)으로 고정함.
      audio.src = URL.createObjectURL(new Blob([blob], { type: "audio/wav" }));
      // 끝까지 받았음을 보내는 쪽에 알림(보내는 쪽은 wire EOF + 이 ACK가 둘 다 필요).
      sendInner({ k: "file_received", id: inner.id, at: inner.at });
    })
    .catch(function () {
      label.textContent = t("voiceMessage") + " — " + t("downloadFailed");
    });
  return wrap;
}
