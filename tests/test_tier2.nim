# Test: Tier 2 spike compiled with jsinn/strings macro
# This should produce clean JS output without Nim string runtime.

import std/jsffi
import ../src/jsinn/strings

type
  JsResponse {.importjs: "Response".} = ref object
  JsRequest {.importjs: "Request".} = ref object
    methodStr {.importjs: "method".}: cstring
    url: cstring

proc newResponse(body: cstring, status: int): JsResponse {.importjs: "new Response(#, {status: #})".}

jsClean:
  proc sanitizeEnvVar(name: cstring): cstring =
    result = name.toUpperAscii().replace("-", "_").replace(".", "_")

  proc fetch(request: JsRequest, env: JsObject): JsResponse {.exportc.} =
    if request.methodStr == "OPTIONS".cstring:
      return newResponse("".cstring, 204)

    let envKey = sanitizeEnvVar("openai-key")
    let msg = "{\"env_key\":\"" & $envKey & "\"}"
    return newResponse(msg.cstring, 200)
