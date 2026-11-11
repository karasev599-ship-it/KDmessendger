const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const calls = fs.readFileSync(path.join(root, 'calls.js'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261111074820_harden_private_call_signaling.sql'),
  'utf8'
);

test('call and inbox channels are private and scoped to the conversation or recipient', () => {
  assert.ok(calls.includes("sb.channel('kd-call-'+conversationId,{config:{private:true}})"));
  assert.ok(calls.includes("sb.channel('kd-call-inbox-'+other,{config:{private:true}})"));
  assert.ok(calls.includes("sb.channel('kd-call-inbox-'+u.id,{config:{private:true}})"));
  assert.ok(calls.includes("payload:{...x,callId,conversationId}"));
  assert.ok(calls.includes("payload:{from:u.id,to:other,callId,conversationId"));
  assert.ok(!calls.includes("sb.channel('kd-call-'+callId)"));
});

test('client refuses group calls and ignores stale or mismatched signaling payloads', () => {
  assert.ok(calls.includes("conv.data?.kind!=='direct'"));
  assert.ok(calls.includes("d.callId!==callId||d.conversationId!==conversationId"));
  assert.ok(calls.includes("x.callId!==callId||x.conversationId!==conversationId"));
  assert.ok(calls.includes("typeof d.conversationId!=='string'"));
});

test('Realtime call policies require private channels and direct conversation membership', () => {
  assert.ok(migration.includes('private is true'));
  assert.ok(migration.includes('kd_messenger_call_receive'));
  assert.ok(migration.includes('kd_messenger_call_send'));
  assert.ok(migration.includes("realtime.topic() ~ '^kd-call-"));
  assert.ok(migration.includes("m.conversation_id::text = substring(realtime.topic() from 9)"));
  assert.ok(migration.includes("c.kind = 'direct'"));
  assert.ok(migration.includes("payload->>'from'"));
  assert.ok(migration.includes("payload->>'conversationId'"));
});

test('call inbox is readable only by its recipient and writable only by a direct-chat participant', () => {
  assert.ok(migration.includes('kd_messenger_call_inbox_receive'));
  assert.ok(migration.includes('kd_messenger_call_inbox_send'));
  assert.ok(migration.includes("substring(realtime.topic() from 15) = (select auth.uid())::text"));
  assert.ok(migration.includes("payload->>'to'"));
  assert.ok(migration.includes("recipient.user_id::text = substring(realtime.topic() from 15)"));
  assert.ok(migration.includes("recipient.user_id <> caller.user_id"));
  assert.ok(migration.includes("caller.conversation_id::text = coalesce(payload->>'conversationId', '')"));
});

test('caller sends a private ring without subscribing to the recipient inbox', () => {
  const create = calls.indexOf("const inbox=sb.channel('kd-call-inbox-'+other,{config:{private:true}});");
  const send = calls.indexOf('sent=await inbox.send(', create);
  const remove = calls.indexOf('await sb.removeChannel(inbox)', create);
  const subscribe = calls.indexOf('inbox.subscribe(', create);
  assert.ok(create >= 0 && send > create && remove > send);
  assert.equal(subscribe, -1, 'sender must not subscribe to the recipient-only inbox topic');
  assert.ok(calls.includes("if(sent!=='ok')throw Error('Не удалось отправить приглашение')"));
});
