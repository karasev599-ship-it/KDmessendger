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

test('call ECDH uses deriveBits and keeps the private and AES keys non-extractable', () => {
  assert.ok(calls.includes("generateKey({name:'ECDH',namedCurve:'P-256'},false,['deriveBits'])"));
  assert.ok(calls.includes("crypto.subtle.deriveBits({name:'ECDH',public:publicKey},keyPair.privateKey,256)"));
  assert.ok(calls.includes("crypto.subtle.importKey('raw',shared,{name:'AES-GCM'},false,['encrypt','decrypt'])"));
  assert.ok(!calls.includes("crypto.subtle.exportKey('raw',cryptoKey)"));
});

test('call E2EE attaches after key derivation or remote track and avoids duplicate transforms', () => {
  assert.ok(calls.includes('e2eeAttached=false,peerKeyConfirmed=false,e2eeUnavailable=false'));
  assert.ok(calls.includes('attachE2EE();return true'));
  assert.ok(calls.includes("pc.ontrack=e=>{remote.srcObject=e.streams[0];setTimeout(attachE2EE,0)}"));
  assert.ok(calls.includes('if(!pc||!cryptoKey||e2eeUnavailable)return'));
  assert.ok(calls.includes("typeof x.createEncodedStreams!=='function'"));
});

test('call UI only labels application-layer E2EE when transforms are attached', () => {
  assert.ok(calls.includes("peerKeyConfirmed=true;if(e2eeAttached)$('#kdSecure').textContent='🔐 E2E • общий секрет совпал'"));
  assert.ok(calls.includes("$('#kdSecure').textContent='🔒 WebRTC DTLS-SRTP'"));
});

test('E2EE transforms are attached to newly arriving RTP tracks without duplicate attachment', () => {
  assert.ok(calls.includes('encryptedSenders=new WeakSet(),encryptedReceivers=new WeakSet()'));
  assert.ok(calls.includes('pendingSenders=senders.filter(x=>!encryptedSenders.has(x))'));
  assert.ok(calls.includes('pendingReceivers=receivers.filter(x=>!encryptedReceivers.has(x))'));
  assert.ok(calls.includes('encryptedSenders.add(x)'));
  assert.ok(calls.includes('encryptedReceivers.add(x)'));
  assert.ok(!calls.includes('if(!pc||!cryptoKey||e2eeAttached||e2eeUnavailable)return'));
});
