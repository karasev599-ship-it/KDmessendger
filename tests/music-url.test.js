const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const music = fs.readFileSync(path.join(__dirname, '..', 'music.js'), 'utf8');

test('private audio URLs are short-lived and refreshed during playback', () => {
  assert.ok(music.includes('createSignedUrl(m.attachment_path,300)'));
  assert.ok(music.includes('signedUrlExpiresAt'));
  assert.ok(music.includes('signedUrlExpiresAt-Date.now()<=60000'));
});
