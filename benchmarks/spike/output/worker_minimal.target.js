// Target: what jsinn should produce for worker_minimal.nim
// This is already close — Tier 1 (pure FFI) is nearly acceptable.
// Minor cleanup: remove unused vars, simplify BeforeRet pattern.

function fetch(request, env) {
  if (request.method === "OPTIONS") {
    return new Response("", { status: 204 });
  }
  return new Response("{\"ok\":true}", { status: 200 });
}
