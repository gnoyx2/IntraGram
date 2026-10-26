// 실제로 번들되는 포털의 브랜딩·대비 계약을 CDN이나 DOM 라이브러리 없이 확인함
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = path.join(__dirname, '../assets/web');
const html = fs.readFileSync(path.join(base, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(base, 'css/layout.css'), 'utf8');
const theme = fs.readFileSync(path.join(base, 'css/theme.css'), 'utf8');

const icon = html.match(/<link\b[^>]*rel="icon"[^>]*href="([^"]+)"/)[1];
assert.ok(icon.startsWith('data:image/svg+xml,'));
const svg = decodeURIComponent(icon.slice('data:image/svg+xml,'.length));
assert.match(svg, /viewBox="0 0 16 16"/);
assert.deepEqual([...svg.matchAll(/<circle cx="(\d+)" cy="8" r="2"/g)].map(m => +m[1]), [4, 12]);
assert.ok(!/<(?:image|script|foreignObject)\b|\bhref=/.test(svg), 'favicon must be self-contained');
for (const [mode, color] of [['light', '#EEF2F6'], ['dark', '#10141B']]) {
  assert.ok(html.includes(`name="theme-color" content="${color}" media="(prefers-color-scheme: ${mode})"`));
}

const focusRules = [...css.matchAll(/([^{}]*:focus-visible[^{}]*)\{([^}]+)\}/g)];
assert.ok(focusRules.length > 0);
assert.ok(focusRules.some(m => /outline:\s*2px solid var\(--accent-ink\)/.test(m[2]) && /outline-offset:\s*var\(--sp-xxs\)/.test(m[2])));
assert.ok(focusRules.every(m => !/outline:\s*(?:none|0)\b/.test(m[2])), 'inputs must retain the same keyboard focus ring');
assert.match(css, /textarea::placeholder\s*\{[^}]*color:\s*var\(--on-surface-variant\)/);
assert.match(css, /\.meta\s*\{[^}]*flex-wrap:\s*wrap/);
assert.match(css, /max-width:\s*min\(240px,\s*100%\)/);
assert.match(css, /prefers-reduced-motion:\s*no-preference/);
assert.match(css, /\.state\.failed\s*\{[^}]*color:\s*var\(--burn\)/);
// 글자 크기는 rem(브라우저 기본 글꼴 크기 설정을 따름). 입력창만 iOS 확대 방지용 16px 하한
assert.deepEqual([...css.matchAll(/font(?:-size)?:\s*(\d+)px/g)].map(m => m[0]), [], 'font sizes must be rem');
assert.match(css, /font-size:\s*max\(16px,\s*1rem\)/);
// 노치 가로 모드, 강제 색상, 낮은 높이, 가상 키보드
assert.match(css, /#log\s*\{[^}]*env\(safe-area-inset-left\)/);
assert.match(css, /\.jump\s*\{[^}]*env\(safe-area-inset-right\)/);
assert.match(css, /@media \(forced-colors: active\)\s*\{[^}]*\.btn[^}]*border:\s*1px solid ButtonText/);
assert.match(css, /@media \(max-height: 360px\)/);
assert.match(html, /interactive-widget=resizes-content/);
assert.match(css, /prefers-reduced-transparency:\s*reduce/);
assert.match(css, /prefers-contrast:\s*more/);
assert.match(css, /backdrop-filter:\s*none/);
assert.match(css, /horizontal-viewport-segments:\s*2/);
assert.match(css, /width:\s*env\(viewport-segment-width 0 0\)/);
assert.match(css, /vertical-viewport-segments:\s*2/);

// 와이드 창에서도 스크롤·드롭은 전체 폭을 쓰고 본문·입력만 네이티브와 같은 840px 열로 정렬함
assert.match(theme, /--chat-width:\s*840px/);
for (const selector of ['#log', 'footer']) {
  const rule = new RegExp(selector + '\\s*\\{[^}]*calc\\(\\(100% - var\\(--chat-width\\)\\) / 2\\)');
  assert.match(css, rule);
}
assert.match(css, /#log\s*\{[^}]*overflow-y:\s*auto/);
assert.match(css, /body\.drag-over #log-wrap::before\s*\{[^}]*inset:\s*var\(--sp-sm\)/);
assert.match(html, /<textarea[^>]*enterkeyhint="send"/);
assert.match(css, /field-sizing:\s*content/);
assert.match(css, /font-variant-numeric:\s*tabular-nums/);
assert.match(css, /@media \(hover: hover\) and \(pointer: fine\)/);
assert.match(css, /\.row:focus-within \.reaction-action\s*\{[^}]*visibility:\s*visible/);
const forced = css.slice(css.indexOf('@media (forced-colors: active)'), css.indexOf('/* 시스템 투명도'));
for (const selector of ['.bubble', 'header', 'footer', '.plain-notice', 'textarea', 'select', ':focus-visible']) {
  assert.ok(forced.includes(selector), selector + ' must have a forced colors rule');
}
assert.match(forced, /border:\s*1px solid CanvasText/);
assert.match(forced, /outline:\s*2px solid Highlight/);
// 👍 버튼은 .btn의 ButtonText 경계를 받고, 켜진 상태는 색이 아니라 aria-pressed와 Highlight 경계로 구분됨
assert.match(forced, /\.reaction-action\[aria-pressed="true"\]\s*\{[^}]*border-color:\s*Highlight/);
assert.match(forced, /\.bubble[^{]*\{[^}]*border:\s*1px solid CanvasText/);

function luminance(hex) {
  return [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
    .reduce((sum, value, i) => sum + value * [0.2126, 0.7152, 0.0722][i], 0);
}
function contrast(fg, bg, opacity = 1) {
  const blended = [0, 2, 4].map(i => Math.round(
    parseInt(fg.slice(i, i + 2), 16) * opacity + parseInt(bg.slice(i, i + 2), 16) * (1 - opacity)
  ).toString(16).padStart(2, '0')).join('');
  const a = luminance(blended), b = luminance(bg);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
assert.equal(contrast('ffffff', '000000'), 21);
assert.equal(contrast('ffffff', 'ffffff'), 1);
for (const [i, block] of [...theme.matchAll(/:root\s*\{([^}]+)\}/g)].entries()) {
  const tokens = Object.fromEntries([...block[1].matchAll(/--([\w-]+):\s*#([a-f\d]{6});/gi)].map(m => [m[1], m[2]]));
  const pairs = [
    ['on-surface', 'surface'], ['on-surface-variant', 'surface-3'],
    ['on-accent', 'action'], ['on-bubble-mine', 'bubble-mine'],
    ['on-bubble-mine', 'bubble-mine-top'], ['on-bubble-theirs', 'bubble-theirs'],
    ['sender', 'bubble-mine-top'], ['sender', 'bubble-mine'],
    ['accent-ink', 'bubble-theirs'], ['burn', 'bubble-mine-top'],
    ['burn', 'bubble-mine'], ['error', 'surface'],
    ['on-bubble-mine', 'bubble-mine-top', 0.85],
    ['on-bubble-mine', 'bubble-mine', 0.85],
    ['on-bubble-theirs', 'bubble-theirs', 0.85],
  ];
  for (const [fg, bg, opacity] of pairs) {
    assert.ok(contrast(tokens[fg], tokens[bg], opacity) >= 7, `${i ? 'dark' : 'light'} ${fg}/${bg}`);
  }
  for (const bg of ['bg', 'surface', 'surface-2', 'surface-3']) {
    assert.ok(contrast(tokens['accent-ink'], tokens[bg]) >= 3, `focus ring/${bg}`);
  }
}
console.log('web design: inline branding, keyboard focus, responsive media and AAA text pairs passed');
