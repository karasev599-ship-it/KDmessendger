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

const qrAndCleanup = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '202611030001_rate_limit_profile_qr_and_dedupe_message_policies.sql'),
  'utf8'
);

test('QR profile resolution applies a per-user limit before checking the supplied token', () => {
  const limitAt = qrAndCleanup.indexOf("check_api_rate_limit('profile_qr_lookup'");
  const tokenCheckAt = qrAndCleanup.indexOf('if p_token is null');
  assert.ok(limitAt >= 0, 'QR lookup must use the shared database rate limiter');
  assert.ok(tokenCheckAt > limitAt, 'invalid token attempts must also count toward the limit');
});

test('duplicate message UPDATE policy and identical index are removed', () => {
  assert.ok(qrAndCleanup.includes('drop policy if exists kd_messages_sender_delete on public.kd_messages'));
  assert.ok(qrAndCleanup.includes('drop index if exists public.kd_messages_conversation_created_idx'));
});

const profileSource = fs.readFileSync(path.join(root, 'profile.js'), 'utf8');
const phonePrivacyMigration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '202611030002_make_phone_discovery_opt_in.sql'),
  'utf8'
);

test('profile editor reads and writes the same phone-discovery preference as the server', () => {
  assert.ok(profileSource.includes("from('kd_user_privacy').select('discover_by_phone')"));
  assert.ok(profileSource.includes('discover_by_phone,updated_at:'));
  assert.doesNotMatch(profileSource, /phone_visible/);
});

test('phone discovery is opt-in for new or missing privacy records', () => {
  assert.match(phonePrivacyMigration, /alter column discover_by_phone set default false/i);
  assert.match(phonePrivacyMigration, /coalesce\(pp\.phone_visible, false\)/i);
  assert.match(phonePrivacyMigration, /coalesce\(up\.discover_by_phone, false\) = true/i);
});

const groupPollMigration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '202611030003_harden_group_poll_rpcs.sql'),
  'utf8'
);

test('group poll creation limits request rate and validates question and option input', () => {
  assert.ok(groupPollMigration.includes("check_api_rate_limit('group_poll_create'"));
  assert.ok(groupPollMigration.includes('between 2 and 10 options'));
  assert.ok(groupPollMigration.includes('1 to 240 characters'));
  assert.ok(groupPollMigration.includes('1 to 100 characters'));
  assert.ok(groupPollMigration.includes('Poll options must be unique'));
  assert.ok(groupPollMigration.includes('from unnest(p_options) as options(option_text)'));
  assert.ok(groupPollMigration.includes('from unnest(p_option_ids) as options(option_id)'));
  const createLimitAt = groupPollMigration.indexOf("check_api_rate_limit('group_poll_create'");
  const createValidationAt = groupPollMigration.indexOf('Poll options must be unique');
  assert.ok(createLimitAt > createValidationAt, 'invalid poll input must not consume a successful-action rate slot');
  const voteLimitAt = groupPollMigration.indexOf("check_api_rate_limit('group_poll_vote'");
  const voteValidationAt = groupPollMigration.indexOf('Single choice poll');
  const voteWriteAt = groupPollMigration.indexOf('delete from public.kd_group_poll_votes');
  assert.ok(voteLimitAt > voteValidationAt && voteLimitAt < voteWriteAt, 'only validated votes should consume a rate slot');
});

test('group poll voting is bounded, rate-limited, member-only, and serialized with closing', () => {
  assert.ok(groupPollMigration.includes("check_api_rate_limit('group_poll_vote'"));
  assert.ok(groupPollMigration.includes('cardinality(p_option_ids) > 10'));
  assert.ok(groupPollMigration.includes('Duplicate poll options are not allowed'));
  assert.ok(groupPollMigration.includes('for update'));
  assert.ok(groupPollMigration.includes('Poll closed'));
  assert.ok(groupPollMigration.includes('Not a member'));
});

const voteRateLimitMigration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '202611030004_ensure_group_poll_vote_rate_limit.sql'),
  'utf8'
);

test('group poll vote rate limiting is present after validation and before vote writes', () => {
  const validationAt = voteRateLimitMigration.indexOf('Single choice poll');
  const limitAt = voteRateLimitMigration.indexOf("check_api_rate_limit('group_poll_vote'");
  const writeAt = voteRateLimitMigration.indexOf('delete from public.kd_group_poll_votes');
  assert.ok(validationAt >= 0 && limitAt > validationAt && limitAt < writeAt);
});
