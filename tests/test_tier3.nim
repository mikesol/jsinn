# Test: Tier 3 spike compiled with jsinn macros
# This should produce clean JS output without Nim string/json runtime.

import std/jsffi
import std/asyncjs
import ../src/jsinn/strings

type
  JsResponse {.importjs: "Response".} = ref object
  JsRequest {.importjs: "Request".} = ref object
    methodStr {.importjs: "method".}: cstring
    url: cstring

proc newResponse(body: cstring, status: int): JsResponse {.importjs: "new Response(#, {status: #})".}
proc jsonReq(req: JsRequest): Future[JsObject] {.importjs: "#.json()".}

jsClean:
  proc fetch(request: JsRequest, env: JsObject): Future[JsResponse] {.async, exportc.} =
    if request.methodStr == "OPTIONS".cstring:
      return newResponse("".cstring, 204)

    if request.methodStr != "POST".cstring:
      return newResponse("{\"error\":\"Method not allowed\"}".cstring, 405)

    let body = await jsonReq(request)
    let url = body.url.to(cstring)

    if url.len == 0:
      return newResponse("{\"error\":\"Missing url\"}".cstring, 400)

    let envKey = "OPENAI_KEY".toUpperAscii()
    let resp = %*{"ok": true, "url": url, "key_env": envKey}
    return newResponse(resp, 200)
