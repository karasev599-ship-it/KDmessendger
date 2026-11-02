const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const features = fs.readFileSync(path.join(root, 'features.js'), 'utf8');
const media = fs.readFileSync(path.join(root, 'media.js'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '202610300001_restrict_message_reaction_values.sql'),
  'utf8'
);

test('stored reactions are escaped in both the data attribute and visible text', () => {
  assert.match(features, /data-r="\$\{esc\(e\)\}">\$\{esc\(e\)\} \$\{n\}/);
  assert.doesNotMatch(features, /data-r="\$\{esc\(e\)\}">\$\{e\}/);
});

test('attachment filenames are inserted as text, never parsed as HTML', () => {
  assert.match(media, /createTextNode\(f\.name\s*\+/);
  assert.doesNotMatch(media, /pv\.innerHTML\s*=/);
});

test('database rejects arbitrary reaction strings', () => {
  assert.match(migration, /check \(reaction in \('❤️', '👍'\)\)/i);
});

test('message escaping preserves literal backslashes while escaping HTML metacharacters', () => {
  const definition = features.match(/esc=s=>String\(s\?\?''\)\.replace\((\/[^/]+\/g),c=>\((\{[^}]+\}\[c\])\)\)/);
  assert.ok(definition, 'escape helper must be present in features.js');
  const esc = new Function(`return (${definition[0].replace(/^esc=/, '')})`)();
  assert.equal(esc('C:\\folder "name" <tag>'), 'C:\\folder &quot;name&quot; &lt;tag&gt;');
});
