// Basic checks for apps.json. Run: node --test tests/*.test.js
// Mirrors Test-CatalogEntry in patch.ps1 - keep the two in sync.
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'apps.json'), 'utf8'));

function reject(app) {
  if (!app || typeof app !== 'object') return 'empty entry';
  if (typeof app.id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(app.id)) return 'id';
  if (typeof app.name !== 'string' || !app.name.trim()) return 'name';
  if (!['asar', 'dir'].includes(app.type)) return 'type';
  if (!Array.isArray(app.bases) || !app.bases.some((b) => typeof b === 'string' && b.trim())) return 'bases';
  if (typeof app.target !== 'string' || !app.target.trim()) return 'target';
  if (/^[\\/]/.test(app.target) || app.target.includes(':') || /(^|[\\/])\.\.([\\/]|$)/.test(app.target)) return 'target';
  if (app.type === 'asar' && !/\.asar$/i.test(app.target)) return 'target';
  if (typeof app.htmlMatch !== 'string' || !app.htmlMatch.trim() || /[\\/:]/.test(app.htmlMatch)) return 'htmlMatch';
  if (app.injectMode && !['inline', 'external'].includes(app.injectMode)) return 'injectMode';
  return null;
}

test('apps.json has a non-empty apps array', () => {
  assert.ok(Array.isArray(catalog.apps) && catalog.apps.length > 0);
});

test('every catalog entry is well formed', () => {
  for (const app of catalog.apps) {
    assert.strictEqual(reject(app), null, `entry ${app && app.id}`);
    assert.strictEqual(typeof app.tested, 'boolean', `tested flag of ${app.id}`);
  }
});

test('ids are unique (case-insensitive)', () => {
  const ids = catalog.apps.map((a) => a.id.toLowerCase());
  assert.strictEqual(new Set(ids).size, ids.length);
});

test('bases only use Windows env-var or absolute paths', () => {
  for (const app of catalog.apps) {
    for (const b of app.bases) assert.match(b, /^(%[A-Za-z0-9_()]+%|[A-Za-z]:)\\/, `${app.id}: ${b}`);
  }
});

test('every catalog id is listed in the README table', () => {
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  for (const app of catalog.apps) assert.ok(readme.includes('| `' + app.id + '`'), `README is missing ${app.id}`);
});

test('the validator rejects bad entries', () => {
  const ok = { id: 'x', name: 'X', type: 'asar', bases: ['%LOCALAPPDATA%\\X'], target: 'resources\\app.asar', htmlMatch: '*.html' };
  assert.strictEqual(reject(ok), null);
  assert.strictEqual(reject({ ...ok, id: '..\\evil' }), 'id');
  assert.strictEqual(reject({ ...ok, type: 'zip' }), 'type');
  assert.strictEqual(reject({ ...ok, bases: [] }), 'bases');
  assert.strictEqual(reject({ ...ok, target: '..\\..\\Windows\\x.asar' }), 'target');
  assert.strictEqual(reject({ ...ok, target: 'C:\\x.asar' }), 'target');
  assert.strictEqual(reject({ ...ok, target: 'resources\\app' }), 'target');
  assert.strictEqual(reject({ ...ok, htmlMatch: '..\\*.html' }), 'htmlMatch');
  assert.strictEqual(reject({ ...ok, injectMode: 'extrenal' }), 'injectMode');
});
