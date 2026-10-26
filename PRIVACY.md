# Privacy / 개인정보 처리 방침

The same text is in the app under *Settings › App › Privacy policy*. 앱의 *설정 › 앱 › 개인정보 처리 방침*에도 같은 내용이 있습니다.

## English

### No server, no account

IntraGram automatically sends no data to the developer or to a cloud service, and needs no sign-up, phone number or email address.

### What stays on this device

Messages, transfer records and session keys live in memory. Burning a message drops its body; up to 512 body-free signed receipts with salted commitments, 64 signed Merkle batches and 64 witness-root observations can remain in RAM. Receipt metadata includes event/subject/attempt IDs, peer IDs and public keys, commitments, policy/outcome, nonce and time. File receipts contain a SHA-256 content digest, which permits known-file comparisons. Evidence, organization credentials and room integrity state are excluded from the vault. Panic wipe blocks new evidence and clears these states synchronously before waiting for shutdown, then clears them again; quitting also clears them. The app writes accepted files and, if enabled in Settings, the optional PIN-sealed vault to disk. On desktop it also records picked download folders to clean up interrupted downloads. Panic erases the vault and folder list; removing the app removes its own folder.

### What leaves this device

Messages go to devices you connect to on this local network. App-to-app 1:1 chats are end-to-end encrypted; the host reads an app group room and room files cross the LAN unencrypted. Browser portal rooms are separate and their traffic is plaintext on Wi-Fi. Optional offline organization credentials contain organization, department, role, issuer, policy, trust snapshot, expiry and the session identity public key. They are held in RAM and presented only after an encrypted app link is established, with proof of key possession; they do not verify the security code. The bundled demo issuer is public and proves no real affiliation; offline revocation checks cover only the selected snapshot. Signed author events and checkpoints accompany app room messages. When you explicitly copy an audit bundle, it contains selected signed receipts, IDs, public keys, commitments, times, salts/proof paths, a signed batch header and any attached witness receipt, without message bodies. Manual witness exchange lets another device inspect that exported metadata and sign its root; no gateway is contacted automatically. Audit copying uses the sensitive clipboard route with a 60-second expiry; Linux clipboard managers may keep copies. You control who receives an exported copy.

### Desktop and browser privacy

macOS does not donate conversations or aliases to Siri, Spotlight or NSUserActivity. Its legacy window sharing restriction cannot guarantee protection against ScreenCaptureKit or Visual Intelligence. Windows uses capture exclusion for supported OS capture APIs and payload-free taskbar flashing instead of Toast history; neither is a security boundary. Linux marks copied text with the KDE secret hint and clears only clipboard contents it owns; clipboard managers may ignore the hint. Browser guests use the host-served inline page with SHA-256 CSP, no external requests or persistent message storage. Cancelled or incomplete downloads are not acknowledged, and burning a voice message or hiding the page releases its audio URL; a voice message released this way says it is no longer available when the page comes back and is not downloaded again. Releasing browser resources cannot guarantee physical memory erasure or prevent OS swap.

### Being found

So that nearby devices can find it, the app announces your display name, platform and port on the local network (mDNS). Anyone on the same network can see them.

### Permissions

Local network: to find and talk to nearby devices. Microphone: only while you record a voice message. Camera: only to scan connection and security codes; no photos are kept. Notifications: new messages while the app is in the background. Photos: only the ones you pick.

### Third parties

IntraGram sends no telemetry or automatic reports to third parties. Your connected peers and the recipients you choose for exported audit bundles receive the data described above. QR codes are read on the device by open-source code that has no network component.

### Questions

Open an issue on the project's GitHub page. Report security problems privately as described in SECURITY.md.

## 한국어

### 서버도 계정도 없음

IntraGram은 개발자나 클라우드 서비스에 데이터를 자동으로 보내지 않고, 가입·전화번호·이메일이 필요 없어요.

### 이 기기에 남는 것

메시지·전송 기록·세션 키는 메모리에 있어요. 메시지를 소각하면 본문 참조를 버리지만 본문 없는 서명 영수증과 Salted 커밋먼트 최대 512건, 서명된 Merkle 배치 64개, 증인 루트 관측 64건은 RAM에 남을 수 있어요. 영수증에는 사건·대상·시도 ID, 피어 ID와 공개키, 커밋먼트, 정책·결과, 난수와 시각이 담겨요. 파일 영수증에는 SHA-256 내용 해시가 있어 아는 파일과 대조할 수 있어요. 증적·조직 자격·방 무결성 상태는 보관소에 저장하지 않아요. 긴급 소거는 종료를 기다리기 전에 신규 증적을 차단하고 이 상태를 동기적으로 비운 뒤, 종료 정리 뒤에도 다시 비워요. 앱을 꺼도 사라져요. 디스크에는 수락한 파일과 설정에서 켠 보관소(선택적 PIN 봉인)를 써요. 컴퓨터에선 끊긴 다운로드 조각을 지우려고 저장 폴더 목록도 적어 둬요. 긴급 소거는 보관소와 그 목록을 지우고, 앱을 지우면 앱 폴더도 지워져요.

### 이 기기 밖으로 나가는 것

메시지는 이 로컬 네트워크에서 연결한 기기로 가요. 앱끼리 1:1 대화는 종단 간 암호화돼요. 앱 그룹 방은 호스트가 읽을 수 있고 방 파일은 LAN에서 평문이에요. 브라우저 포털 방은 앱 그룹 방과 별개이며 Wi-Fi에서 평문이에요. 선택적으로 제시하는 오프라인 조직 자격에는 기관·부서·역할·발급기관·정책·신뢰 스냅샷·만료와 이번 실행의 신원 공개키가 들어가요. RAM에만 두고 암호화된 앱 링크가 선 뒤 키 소유 증명과 함께 제시하며, 보안 코드 확인과는 별개예요. 기본 시연 발급기관은 공개돼 있어 실제 소속을 보증하지 않고, 오프라인 폐기 확인은 선택한 스냅샷까지만 반영해요. 앱 방 메시지에는 작성자 서명 사건과 체크포인트가 따라가요. 직접 감사 번들을 복사하면 선택한 서명 영수증·ID·공개키·커밋먼트·시각·salt·증명 경로·서명된 배치 헤더·연결된 증인 영수증이 담기며 메시지 본문은 없어요. 수동 증인 교환에서는 다른 기기가 이 반출 메타데이터를 보고 루트에 서명해요. 자동으로 게이트웨이에 보내지 않아요. 감사 복사는 60초 만료의 민감 클립보드 경로를 쓰지만 Linux 클립보드 관리자는 사본을 남길 수 있어요. 반출본을 누구에게 줄지는 사용자가 정해요.

### 데스크톱과 브라우저 개인정보

macOS는 대화나 별칭을 Siri·Spotlight·NSUserActivity에 기부하지 않아요. 레거시 창 공유 제한으로 ScreenCaptureKit이나 Visual Intelligence 캡처 차단을 보장할 수는 없어요. Windows는 지원되는 OS 캡처 API에 캡처 제외를 요청하고, Toast 기록 대신 내용 없는 작업 표시줄 점멸을 써요. 둘 다 보안 경계는 아니에요. Linux는 복사한 글에 KDE 비밀 힌트를 붙이고 앱 소유 클립보드만 비워요. 클립보드 관리자가 힌트를 무시할 수는 있어요. 브라우저 게스트는 SHA-256 CSP가 적용된 호스트의 인라인 페이지를 쓰며 외부 요청이나 영구 메시지 저장을 하지 않아요. 취소되거나 미완료인 다운로드는 수신 확인하지 않고, 음성 소각이나 페이지 숨김 때 음성 URL을 해제해요. 이렇게 해제한 음성은 페이지로 돌아와도 다시 받지 않고 더 이상 재생할 수 없다고 표시해요. 브라우저 자원 해제로 물리 메모리 소거나 OS 스왑 방지까지 보장할 수는 없어요.

### 기기 찾기

근처 기기가 찾을 수 있게 앱이 표시 이름·플랫폼·포트를 로컬 네트워크에 알려요(mDNS). 같은 네트워크의 누구나 볼 수 있어요.

### 권한

로컬 네트워크: 근처 기기를 찾고 대화하려고. 마이크: 음성 메시지를 녹음하는 동안만. 카메라: 연결 코드와 보안 코드를 스캔할 때만, 사진은 남기지 않아요. 알림: 앱이 백그라운드일 때 새 메시지. 사진: 고른 것만.

### 제3자

IntraGram은 제3자에게 원격 분석이나 자동 보고를 보내지 않아요. 연결한 피어와 사용자가 고른 감사 번들 수신자는 위에서 설명한 데이터를 받아요. QR 코드는 네트워크를 쓰지 않는 오픈소스 코드가 기기 안에서 읽어요.

### 문의

프로젝트 GitHub 페이지에 이슈를 남겨 주세요. 보안 문제는 SECURITY.md의 비공개 신고 절차를 따라 주세요.

Engineering verification / 엔지니어링 검증 (2026-10-26): **1,411 Flutter tests**, **21 browser guard groups**, **88 web design assertions**, 0 analyzer issues. All ten required commands exit 0; the macOS debug build succeeded with third-party plugin warnings and a local CoreSimulator version diagnostic. Headless Firefox 158 checked the app-served page under its CSP, download cancellation, BFCache voice release and forced colors. Windows and Linux debug builds passed in private CI; physical target-OS QA remains pending. Test counts do not certify capture prevention or memory erasure.

Capture API scope: [Apple NSWindow sharing type](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum), [Microsoft SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity).
