// 피어가 알려 준 주소(방 멤버의 직접 주소 sh/sp)는 전부 여기서 정규화하고 검증한 뒤에만 URL·fetch에 씀.
// 앱의 NetworkGuard.parsePeerEndpoint와 같은 정책: 정규 dotted-decimal RFC 1918 IPv4와 1..65535 포트만 받고
// loopback·APIPA·IPv6·hostname·userinfo·비정규 표기(010.0.0.1은 WHATWG URL에선 8진 8.0.0.1)는 전부 거부함.
// 테스트·내부용 loopback 예외는 이 파일 밖이라 사용자나 wire가 고를 수 없음
var OCTET = "(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)";
var IPV4_RE = new RegExp("^" + [OCTET, OCTET, OCTET, OCTET].join("\\.") + "$");

// port는 number나 순수 10진 문자열만 허용해 Number('0x1F90') 같은 암묵적 변환을 차단함
function parseLanEndpoint(host, port) {
  if (typeof host !== "string") return null;
  var m = IPV4_RE.exec(host);
  if (!m) return null;
  var p = typeof port === "number" ? port
    : (typeof port === "string" && /^[1-9]\d{0,4}$/.test(port) ? Number(port) : NaN);
  if (!Number.isInteger(p) || p < 1 || p > 65535) return null;
  var o = m.slice(1).map(Number);
  for (var i = 0; i < 4; i++) if (o[i] > 255) return null;
  var isPrivate =
    o[0] === 10 ||
    (o[0] === 172 && o[1] >= 16 && o[1] <= 31) ||
    (o[0] === 192 && o[1] === 168);
  return isPrivate ? { host: o.join("."), port: p } : null;
}

// 검증한 endpoint로 URL을 만들고, 브라우저 URL 파서가 host·port를 검증한 값 그대로 읽었는지 다시 봄 (파서 불일치 방어).
// userinfo가 붙으면 거부함. scheme 기본 포트(80)는 url.port가 빈 문자열이라 따로 처리함
function endpointUrl(ep, path, scheme) {
  if (!ep) return null;
  var url;
  try { url = new URL(path, scheme + "://" + ep.host + ":" + ep.port + "/"); } catch (e) { return null; }
  var port = url.port === "" ? 80 : Number(url.port);
  if (url.hostname !== ep.host || port !== ep.port || url.username || url.password) return null;
  return url.href;
}

// peer 대상 요청의 유일한 출구. redirect:'error'(3xx로 토큰·바이트가 딴 데로 안 가게)와 cache:'no-store'를 늘 강제하고,
// 같은 출처나 RFC1918 endpoint가 아닌 URL은 요청을 아예 안 만듦. 새 peer 요청도 이 함수를 거쳐야 함
// (fetch를 직접 부르는 코드는 tool/browser_guard_test.js가 정적 검사로 잡음)
function peerFetch(url, init) {
  var target;
  try { target = new URL(url, location.href); } catch (e) { return Promise.reject(new TypeError("bad peer url")); }
  var sameOrigin = target.origin === location.origin;
  var port = target.port === "" ? 80 : Number(target.port);
  if (!sameOrigin && (target.protocol !== "http:" || target.username || target.password ||
      !parseLanEndpoint(target.hostname, port))) {
    return Promise.reject(new TypeError("peer url not allowed"));
  }
  var opts = {};
  for (var k in init || {}) opts[k] = init[k];
  opts.redirect = "error";
  opts.cache = "no-store";
  return fetch(target.href, opts);
}

// 파일·음성 내려받기 URL을 만듦. sh/sp(방 멤버의 직접 주소)가 있으면 parseLanEndpoint를 통과한 값으로만 만들고,
// 실패하면 호스트로 대체하지 않고 null을 반환함. 없으면 호스트(같은 출처)로 요청함.
// 호스트가 사설 IPv4 없이 링크 로컬(169.254)이나 IPv6 ULA로 떠 있으면 sh가 그 주소라 위 검증을 못 넘어서,
// sh/sp가 이 페이지를 준 호스트 자신이면 검증 대신 같은 출처로 받음
function resolveDownloadUrl(id, sh, sp) {
  var path = "/api/download/" + encodeURIComponent(id);
  var self = new URL(path, location.href).href;
  if (!sh && !sp) return self;
  var shHost = String(sh).indexOf(":") >= 0 ? "[" + sh + "]" : String(sh);
  if (shHost + ":" + sp === location.host) return self;
  return endpointUrl(parseLanEndpoint(sh, sp), path, "http");
}
