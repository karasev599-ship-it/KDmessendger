const SUPABASE_URL = 'https://qqofizfqkctycyeafgsa.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxb2ZpemZxa2N0eWN5ZWFmZ3NhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5OTM4NTQsImV4cCI6MjEwMjU2OTg1NH0.QJVb9ZuHcl89Vr11NJJiPuzASlqIFgXhR9goWk1_YAE';
const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 10;
const rate = new Map();

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Используй POST.' });
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return res.status(503).json({ error: 'AI ещё не настроен: добавь OPENAI_API_KEY в Vercel → Settings → Environment Variables.' });

  const authorization = req.headers.authorization || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token) return res.status(401).json({ error: 'Войди в KD Messenger, чтобы пользоваться AI.' });

  try {
    const verify = await fetch(SUPABASE_URL + '/auth/v1/user', {
      headers: { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + token }
    });
    if (!verify.ok) return res.status(401).json({ error: 'Сессия недействительна. Войди снова.' });
    const account = await verify.json();
    if (!account || !account.id) return res.status(401).json({ error: 'Не удалось проверить аккаунт.' });

    const now = Date.now();
    const entry = rate.get(account.id);
    if (entry && now - entry.start < WINDOW_MS && entry.count >= MAX_PER_WINDOW) {
      return res.status(429).json({ error: 'Слишком много запросов. Подожди минуту и попробуй снова.' });
    }
    if (!entry || now - entry.start >= WINDOW_MS) rate.set(account.id, { start: now, count: 1 });
    else entry.count += 1;

    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const message = typeof body.message === 'string' ? body.message.trim() : '';
    if (!message) return res.status(400).json({ error: 'Напиши вопрос.' });
    if (message.length > 6000) return res.status(413).json({ error: 'Сообщение слишком длинное (максимум 6000 символов).' });

    const ai = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-5.4',
        instructions: 'Ты KD AI — универсальный помощник внутри KD Messenger. Помогай с любыми вопросами и задачами: письма, тексты, идеи, обучение, программирование, анализ информации и повседневные задачи. Отвечай на языке пользователя, понятно и по делу. Не утверждай, что у тебя есть доступ к интернету, файлам или функциям, если их не предоставили. Для финансовых и медицинских тем объясняй ограничения и не выдавай догадки за факты.',
        input: message,
        max_output_tokens: 1200,
        store: false
      })
    });
    const result = await ai.json();
    if (!ai.ok) {
      console.error('OpenAI Responses API error', ai.status, result?.error?.type || result?.error?.code || 'unknown');
      if (ai.status === 401) return res.status(502).json({ error: 'OpenAI не принял API-ключ. Проверь OPENAI_API_KEY в Vercel.' });
      if (ai.status === 429) return res.status(429).json({ error: 'Лимит OpenAI или баланс API исчерпан. Проверь настройки аккаунта OpenAI.' });
      return res.status(502).json({ error: 'OpenAI временно не смог обработать запрос. Попробуй ещё раз.' });
    }
    const reply = result.output_text || (result.output || []).flatMap(item => item.content || []).filter(part => part.type === 'output_text').map(part => part.text).join('\n').trim();
    if (!reply) return res.status(502).json({ error: 'AI вернул пустой ответ. Попробуй переформулировать вопрос.' });
    return res.status(200).json({ reply });
  } catch (error) {
    console.error('KD AI request failed', error?.message || 'unknown error');
    return res.status(500).json({ error: 'Не удалось обработать запрос. Попробуй ещё раз.' });
  }
};
