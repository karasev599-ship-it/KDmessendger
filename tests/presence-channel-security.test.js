const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const realtime = fs.readFileSync(path.join(root, 'realtime.js'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261111075834_secure_private_conversation_presence.sql'),
  'utf8'
);

test('conversation presence uses a private channel', () => {
  assert.ok(realtime.includes("sb.channel('kd-presence-'+cid,{config:{private:true,presence:{key:user.id}}})"));
  assert.ok(!realtime.includes("sb.channel('kd-presence-'+cid,{config:{presence:{key:user.id}}})"));
});

test('presence read and write policies require private channel and conversation membership', () => {
  assert.ok(migration.includes('kd_messenger_presence_receive'));
  assert.ok(migration.includes('kd_messenger_presence_send'));
  assert.ok(migration.includes('private is true'));
  assert.ok(migration.includes("extension = 'presence'"));
  assert.ok(migration.includes("realtime.topic() ~ '^kd-presence-"));
  assert.ok(migration.includes('substring(realtime.topic() from 13)'));
  assert.ok(migration.includes('m.user_id = (select auth.uid())'));
});
