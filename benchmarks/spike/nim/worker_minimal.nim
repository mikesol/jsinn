# Tier 1: Minimal Worker using only JS FFI — no Nim stdlib
import std/jsffi

type
  JsResponse {.importjs: "Response".} = ref object
  JsRequest {.importjs: "Request".} = ref object
    methodStr {.importjs: "method".}: cstring
    url: cstring

proc newResponse(body: cstring, status: int): JsResponse {.importjs: "new Response(#, {status: #})".}

proc fetch(request: JsRequest, env: JsObject): JsResponse {.exportc.} =
  if request.methodStr == "OPTIONS".cstring:
    return newResponse("".cstring, 204)
  return newResponse("{\"ok\":true}".cstring, 200)
