interface Env {
  SHARES: KVNamespace;
}

interface ShareData {
  content: string;
  createdAt: number;
  updatedAt: number;
}

const MAX_CONTENT_SIZE = 100 * 1024; // 100KB

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

export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { env, params } = context;
  const id = params.id as string;
  
  if (!id || !/^[a-zA-Z0-9]{8,12}$/.test(id)) {
    return new Response(JSON.stringify({ error: '无效的分享链接' }), {
      status: 400,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  const data = await env.SHARES.get(`share:${id}`);
  
  if (!data) {
    return new Response(JSON.stringify({ error: '分享不存在或已过期' }), {
      status: 404,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  const shareData: ShareData = JSON.parse(data);
  
  return new Response(JSON.stringify({
    id,
    content: shareData.content,
    createdAt: shareData.createdAt,
    updatedAt: shareData.updatedAt,
  }), {
    headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
  });
};

export const onRequestPut: PagesFunction<Env> = async (context) => {
  const { env, params, request } = context;
  const id = params.id as string;
  
  if (!id || !/^[a-zA-Z0-9]{8,12}$/.test(id)) {
    return new Response(JSON.stringify({ error: '无效的分享链接' }), {
      status: 400,
      headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    });
  }
  
  const existingData = await env.SHARES.get(`share:${id}`);
  
  if (!existingData) {
    return new Response(JSON.stringify({ error: '分享不存在或已过期' }), {
      status: 404,
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
  
  const content = body.content;
  
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
  
  const existing: ShareData = JSON.parse(existingData);
  const now = Date.now();
  
  const updatedData: ShareData = {
    content,
    createdAt: existing.createdAt,
    updatedAt: now,
  };
  
  await env.SHARES.put(`share:${id}`, JSON.stringify(updatedData), {
    expirationTtl: 30 * 24 * 60 * 60, // 30 days from now (refreshes on edit)
  });
  
  return new Response(JSON.stringify({
    id,
    content: updatedData.content,
    updatedAt: updatedData.updatedAt,
  }), {
    headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
  });
};
