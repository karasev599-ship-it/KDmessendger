const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261111074447_enforce_message_media_path_shape.sql'),
  'utf8'
);
const media = fs.readFileSync(path.join(root, 'media.js'), 'utf8');

test('message uploads use the canonical conversation/user/file path', () => {
  assert.ok(media.includes("path=id+'/'+u.id+'/'+crypto.randomUUID()+'.'+ext(type)"));
});

test('Storage insert policy accepts only the same three-segment path shape as deletion', () => {
  assert.ok(migration.includes('drop policy if exists kd_messenger_media_insert on storage.objects'));
  assert.ok(migration.includes('create policy kd_messenger_media_insert'));
  assert.ok(migration.includes("cardinality(string_to_array(objects.name, '/')) = 3"));
  assert.ok(migration.includes("split_part(objects.name, '/', 1) ~*"));
  assert.ok(migration.includes("split_part(objects.name, '/', 2) = (select auth.uid())::text"));
  assert.ok(migration.includes("split_part(objects.name, '/', 3) <> ''"));
  assert.ok(migration.includes('public.kd_conversation_members cm'));
  assert.ok(migration.includes('cm.user_id = (select auth.uid())'));
});
