const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const contacts = fs.readFileSync(path.join(root, 'contacts.js'), 'utf8');
const privacy = fs.readFileSync(path.join(root, 'privacy.js'), 'utf8');

test('phonebook clients send bounded batches to the lookup RPC', () => {
  assert.ok(contacts.includes('i+=100') && contacts.includes('variants.slice(i,i+100)'));
  assert.ok(privacy.includes('i+=100') && privacy.includes('variants.slice(i,i+100)'));
});

test('phonebook clients reject numbers outside the supported 7–15 digit range', () => {
  assert.ok(contacts.includes('d.length<7||d.length>15'));
  assert.ok(privacy.includes('d.length<7||d.length>15'));
});

test('VCF import is bounded before reading the file into memory', () => {
  assert.ok(contacts.includes('file.size>2097152'));
});

test('rate-limit errors are surfaced as a retryable phonebook message', () => {
  assert.ok(contacts.includes("x.error.code==='P0001'"));
  assert.ok(privacy.includes("search.error.code==='P0001'"));
});

const migration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261110075517_fix_phone_lookup_number_validation.sql'),
  'utf8'
);

test('phone lookup validates E.164-sized candidates and charges by batch size', () => {
  assert.ok(migration.includes("item.phone !~ '^[+]?[0-9]{7,15}$'"));
  assert.ok(migration.includes('ceil(cardinality(p_phones)::numeric / 100)::integer'));
  assert.ok(migration.includes("check_api_rate_limit('phone_lookup'"));
  assert.ok(migration.includes('60, 20'));
  assert.ok(migration.includes('coalesce(up.discover_by_phone, false) = true'));
});
