# Tier 2: Worker with Nim string operations (tests stdlib pull-in)
import std/jsffi
import std/strutils

type
  JsResponse {.importjs: "Response".} = ref object
  JsRequest {.importjs: "Request".} = ref object
    methodStr {.importjs: "method".}: cstring
    url: cstring

proc newResponse(body: cstring, status: int): JsResponse {.importjs: "new Response(#, {status: #})".}

proc sanitizeEnvVar(name: string): string =
  result = name.toUpperAscii().replace("-", "_").replace(".", "_")

proc fetch(request: JsRequest, env: JsObject): JsResponse {.exportc.} =
  if request.methodStr == "OPTIONS".cstring:
    return newResponse("".cstring, 204)

  let envKey = sanitizeEnvVar("openai-key")
  let msg = "{\"env_key\":\"" & envKey & "\"}"
  return newResponse(msg.cstring, 200)
