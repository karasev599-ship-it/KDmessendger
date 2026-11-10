const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'migrations', '20261110090630_require_membership_for_message_media_delete.sql'),
  'utf8'
);

test('message attachment deletion requires the current conversation membership', () => {
  assert.match(migration, /drop policy if exists kd_messenger_media_delete on storage\.objects/i);
  assert.match(migration, /create policy kd_messenger_media_delete[\s\S]*for delete[\s\S]*to authenticated/i);
  assert.ok(migration.includes("bucket_id = 'kd-messenger'"));
  assert.ok(migration.includes("split_part(name, '/', 2) = (select auth.uid())::text"));
  assert.ok(migration.includes("cardinality(string_to_array(name, '/')) = 3"));
  assert.ok(migration.includes('public.kd_conversation_members'));
  assert.ok(migration.includes('cm.user_id = (select auth.uid())'));
  assert.ok(migration.includes("split_part(objects.name, '/', 1) ~*"));
});

test('message attachment deletion does not grant access to another user folder', () => {
  assert.ok(migration.includes("split_part(name, '/', 2) = (select auth.uid())::text"));
});
