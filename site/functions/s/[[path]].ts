interface Env {
  ASSETS: Fetcher;
}

export const onRequest: PagesFunction<Env> = async (context) => {
  const { env, request } = context;
  
  // Serve the share.html page for all /s/* routes
  const url = new URL(request.url);
  url.pathname = '/share.html';
  
  const response = await env.ASSETS.fetch(new Request(url.toString(), request));
  
  // Return with correct content type
  return new Response(response.body, {
    status: response.status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-cache',
    },
  });
};
