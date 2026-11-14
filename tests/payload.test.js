// Runs the JS payload embedded in patch.ps1 against a tiny fake DOM.
// Run: node --test tests/*.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ps1 = fs.readFileSync(path.join(__dirname, '..', 'patch.ps1'), 'utf8').replace(/\r\n/g, '\n');
const m = ps1.match(/\$RtlPayloadJs = @'\n([\s\S]*?)\n'@/);

function el(tag, text, opts = {}) {
  const attrs = { ...(opts.attrs || {}) };
  return {
    tag, textContent: text, attrs,
    hasAttribute: (n) => n in attrs,
    setAttribute: (n, v) => { attrs[n] = v; },
    closest: () => (opts.inCode ? {} : null),
  };
}

function run(blocks) {
  const styles = [];
  const document = {
    readyState: 'complete',
    head: { appendChild: (s) => styles.push(s) },
    documentElement: {},
    body: { querySelectorAll: () => blocks },
    getElementById: (id) => styles.find((s) => s.id === id) || null,
    createElement: () => ({}),
    addEventListener: () => {},
  };
  const window = { requestAnimationFrame: (f) => f() };
  const observers = [];
  function MutationObserver(cb) { this.cb = cb; this.observe = () => {}; observers.push(this); }
  vm.runInNewContext(m[1], { window, document, MutationObserver, setTimeout });
  return { window, styles, observers };
}

test('payload is found in patch.ps1 and is pure ASCII', () => {
  assert.ok(m, 'payload here-string not found');
  assert.ok(/^[\x00-\x7F]*$/.test(m[1]), 'payload must stay ASCII');
  assert.ok(!m[1].includes("\n'@"), 'payload must not terminate the here-string');
  assert.ok(!/<\/script/i.test(m[1]), 'payload must not close the inline <script>');
});

test('stamps dir=auto only on RTL blocks outside code, and never overrides dir', () => {
  const he = el('p', '\u05e9\u05dc\u05d5\u05dd world');
  const ar = el('li', '\u0645\u0631\u062d\u0628\u0627');
  const en = el('p', 'hello');
  const code = el('p', '\u05e9\u05dc\u05d5\u05dd', { inCode: true });
  const fixed = el('p', '\u05e9\u05dc\u05d5\u05dd', { attrs: { dir: 'ltr' } });
  const { styles, window } = run([he, ar, en, code, fixed]);
  assert.strictEqual(he.attrs.dir, 'auto');
  assert.strictEqual(ar.attrs.dir, 'auto');
  assert.strictEqual(en.attrs.dir, undefined);
  assert.strictEqual(code.attrs.dir, undefined);
  assert.strictEqual(fixed.attrs.dir, 'ltr');
  assert.strictEqual(window.__electronRtlPatch, true);
  assert.strictEqual(styles.length, 1);
  assert.strictEqual(styles[0].id, 'electron-rtl-style');
  assert.match(styles[0].textContent, /unicode-bidi: plaintext/);
});

test('style is injected once even when the observer fires again', () => {
  const { styles, observers } = run([]);
  observers[0].cb();
  observers[0].cb();
  assert.strictEqual(styles.length, 1);
});

test('patch.ps1 marker, sidecar name and script tag stay consistent', () => {
  assert.match(ps1, /\$Marker\s+= 'electron-rtl-patch'/);
  assert.match(ps1, /\$SidecarName\s+= 'electron-rtl-patch\.js'/);
  assert.ok(ps1.includes('<script id=""$Marker"" src=""./$SidecarName""></script>'));
  assert.ok(ps1.includes('<script id=""$Marker"">'));
});
