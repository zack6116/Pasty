interface Env {
  SHARES: KVNamespace;
}

interface ShareData {
  content: string;
  createdAt: number;
  updatedAt: number;
  ip?: string;
}

const MAX_CONTENT_SIZE = 100 * 1024; // 100KB
const RATE_LIMIT_WINDOW = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX = 10; // 10 creates per minute per IP

function generateId(): string {
  const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let id = '';
  const array = new Uint8Array(10);
  crypto.getRandomValues(array);
  for (let i = 0; i < 10; i++) {
    id += chars[array[i] % chars.length];
  }
  return id;
}

async function checkRateLimit(env: Env, ip: string): Promise<boolean> {
  const key = `ratelimit:${ip}`;
  const data = await env.SHARES.get(key);
  const now = Date.now();
  
  if (!data) {
    await env.SHARES.put(key, JSON.stringify({ count: 1, windowStart: now }), {
      expirationTtl: 120,
    });
    return true;
  }
  
  const parsed = JSON.parse(data);
  if (now - parsed.windowStart > RATE_LIMIT_WINDOW) {
    await env.SHARES.put(key, JSON.stringify({ count: 1, windowStart: now }), {
      expirationTtl: 120,
    });
    return true;
  }
  
  if (parsed.count >= RATE_LIMIT_MAX) {
    return false;
  }
  
  await env.SHARES.put(key, JSON.stringify({ count: parsed.count + 1, windowStart: parsed.windowStart }), {
    expirationTtl: 120,
  });
  return true;
}

function corsHeaders(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { headers: corsHeaders() });
};

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { env, request } = context;
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  
  if (!await checkRateLimit(env, ip)) {
    return new Response(JSON.stringify({ error: '请求过于频繁，请稍后再试' }), {
      status: 429,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  let body: { content?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: '无效的请求格式' }), {
      status: 400,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  const content = body.content ?? '';
  
  if (typeof content !== 'string') {
    return new Response(JSON.stringify({ error: '内容必须是文本' }), {
      status: 400,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  if (new TextEncoder().encode(content).length > MAX_CONTENT_SIZE) {
    return new Response(JSON.stringify({ error: '内容超过 100KB 限制' }), {
      status: 400,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  const id = generateId();
  const now = Date.now();
  const shareData: ShareData = {
    content,
    createdAt: now,
    updatedAt: now,
  };
  
  await env.SHARES.put(`share:${id}`, JSON.stringify(shareData), {
    expirationTtl: 30 * 24 * 60 * 60, // 30 days
  });
  
  return new Response(JSON.stringify({ id, url: `/s/${id}` }), {
    status: 201,
    headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
  });
};
