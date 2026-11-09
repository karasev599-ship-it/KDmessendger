const test = require('node:test');
const assert = require('node:assert/strict');
const handler = require('../api/ai');

function createResponse() {
  return {
    statusCode: null,
    headers: {},
    payload: null,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.payload = payload;
      return payload;
    }
  };
}

async function withMockedEnvironment(values, run) {
  const keys = ['OPENAI_API_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'NODE_ENV'];
  const previous = Object.fromEntries(keys.map(key => [key, process.env[key]]));
  const previousFetch = global.fetch;

  for (const key of keys) {
    if (Object.hasOwn(values, key)) process.env[key] = values[key];
    else delete process.env[key];
  }

  try {
    await run();
  } finally {
    for (const key of keys) {
      if (previous[key] === undefined) delete process.env[key];
      else process.env[key] = previous[key];
    }
    global.fetch = previousFetch;
  }
}

test('invalid AI payloads are rejected before the shared rate limiter is called', async () => {
  await withMockedEnvironment({
    OPENAI_API_KEY: 'test-openai-key',
    SUPABASE_SERVICE_ROLE_KEY: 'test-service-role'
  }, async () => {
    const calls = [];
    global.fetch = async url => {
      calls.push(String(url));
      return { ok: true, json: async () => ({ id: 'user-1' }) };
    };

    const cases = [
      { body: '{', status: 400 },
      { body: 'null', status: 400 },
      { body: '[]', status: 400 },
      { body: { message: '   ' }, status: 400 },
      { body: { message: 'x'.repeat(6001) }, status: 413 }
    ];

    for (const item of cases) {
      const res = createResponse();
      await handler({
        method: 'POST',
        headers: { authorization: 'Bearer test-token' },
        body: item.body
      }, res);

      assert.equal(res.statusCode, item.status);
      assert.equal(calls.length, cases.indexOf(item) + 1);
      assert.match(calls.at(-1), /\/auth\/v1\/user$/);
    }
  });
});

test('missing authentication is rejected before revealing AI configuration state', async () => {
  await withMockedEnvironment({}, async () => {
    let calls = 0;
    global.fetch = async () => {
      calls += 1;
      throw new Error('fetch must not be called without a bearer token');
    };

    const res = createResponse();
    await handler({ method: 'POST', headers: {}, body: { message: 'hello' } }, res);

    assert.equal(res.statusCode, 401);
    assert.equal(calls, 0);
  });
});

test('production AI requests fail closed when shared rate limiting is not configured', async () => {
  await withMockedEnvironment({
    OPENAI_API_KEY: 'test-openai-key',
    NODE_ENV: 'production'
  }, async () => {
    const calls = [];
    global.fetch = async url => {
      calls.push(String(url));
      if (String(url).endsWith('/auth/v1/user')) {
        return { ok: true, json: async () => ({ id: 'user-1' }) };
      }
      throw new Error('Rate limiting and OpenAI must not be called without the shared limiter secret');
    };

    const res = createResponse();
    await handler({
      method: 'POST',
      headers: { authorization: 'Bearer test-token' },
      body: { message: 'Привет' }
    }, res);

    assert.equal(res.statusCode, 503);
    assert.equal(calls.length, 1);
    assert.ok(calls[0].endsWith('/auth/v1/user'));
  });
});

test('valid AI requests pass authentication and rate limiting before OpenAI is called', async () => {
  await withMockedEnvironment({
    OPENAI_API_KEY: 'test-openai-key',
    SUPABASE_SERVICE_ROLE_KEY: 'test-service-role'
  }, async () => {
    const calls = [];
    global.fetch = async (url, options = {}) => {
      const target = String(url);
      calls.push(target);

      if (target.endsWith('/auth/v1/user')) {
        return { ok: true, json: async () => ({ id: 'user-1' }) };
      }
      if (target.endsWith('/rest/v1/rpc/check_api_rate_limit')) {
        return { ok: true, json: async () => true };
      }
      if (target === 'https://api.openai.com/v1/responses') {
        return { ok: true, json: async () => ({ output_text: 'Готово' }) };
      }
      throw new Error('Unexpected network request: ' + target);
    };

    const res = createResponse();
    await handler({
      method: 'POST',
      headers: { authorization: 'Bearer test-token' },
      body: { message: 'Привет' }
    }, res);

    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.payload, { reply: 'Готово' });
    assert.match(calls[0], /\/auth\/v1\/user$/);
    assert.match(calls[1], /\/rest\/v1\/rpc\/check_api_rate_limit$/);
    assert.equal(calls[2], 'https://api.openai.com/v1/responses');
  });
});
