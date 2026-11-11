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

test('voice attachment URL refresh preserves playback position and state', () => {
  const listener = media.indexOf("media.addEventListener('loadedmetadata',function restore()");
  const source = media.indexOf('media.src=q.data.signedUrl;media.load()');
  assert.ok(media.includes('const wasPlaying=!media.paused,currentTime=media.currentTime'));
  assert.ok(listener >= 0 && source > listener, 'restore listener must be registered before loading the refreshed URL');
  assert.ok(media.includes('if(wasPlaying)media.play().catch(()=>{})'));
  assert.ok(media.includes('media.currentTime=Math.min(currentTime,media.duration||currentTime)'));
});

test('music player registers its restore listener before replacing the signed URL', () => {
  const music = fs.readFileSync(path.join(__dirname, '..', 'music.js'), 'utf8');
  const listener = music.indexOf("a.addEventListener('loadedmetadata',function restore()");
  const source = music.indexOf('a.src=r.data.signedUrl;');
  const load = music.indexOf('a.load();return true', source);
  assert.ok(listener >= 0 && source > listener && load > source);
  assert.ok(music.includes('if(wasPlaying)a.play().catch(()=>{})'));
  assert.ok(music.includes('a.currentTime=Math.min(currentTime,a.duration||currentTime)'));
});
