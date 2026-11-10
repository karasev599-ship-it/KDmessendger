const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const media = fs.readFileSync(path.join(__dirname, '..', 'media.js'), 'utf8');

test('private attachment URLs are short-lived and refreshed before expiry', () => {
  assert.ok(media.includes('createSignedUrl(path,300)'));
  assert.ok(media.includes('expiresAt-60000'));
  assert.ok(media.includes('mediaExpiresAt'));
});
