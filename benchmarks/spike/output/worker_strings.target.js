// Target: what jsinn should produce for worker_strings.nim
// Today this is 684 lines / 18 KB. Target: ~25 lines.

function sanitizeEnvVar(name) {
  return name.toUpperCase().replace("-", "_").replace(".", "_");
}

function fetch(request, env) {
  if (request.method === "OPTIONS") {
    return new Response("", { status: 204 });
  }

  const envKey = sanitizeEnvVar("openai-key");
  const msg = '{"env_key":"' + envKey + '"}';
  return new Response(msg, { status: 200 });
}
