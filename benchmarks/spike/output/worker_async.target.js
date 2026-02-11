// Target: what jsinn should produce for worker_async.nim
// Today this is 1545 lines / 57 KB. Target: ~30 lines.

async function fetch(request, env) {
  if (request.method === "OPTIONS") {
    return new Response("", { status: 204 });
  }

  if (request.method !== "POST") {
    return new Response('{"error":"Method not allowed"}', { status: 405 });
  }

  const body = await request.json();
  const url = body.url;

  if (url.length === 0) {
    return new Response('{"error":"Missing url"}', { status: 400 });
  }

  const envKey = "OPENAI_KEY".toUpperCase();
  const resp = JSON.stringify({ ok: true, url: url, key_env: envKey });
  return new Response(resp, { status: 200 });
}
