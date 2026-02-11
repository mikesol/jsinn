## main — Cloudflare Worker handler for placeholders.dev
## Port of: placeholders.dev/src/index.ts
##
## Skips: analytics (Cloudflare-specific), HTMLRewriter (Cloudflare-specific)

import std/jsffi
import std/asyncjs
import std/strutils
import std/options
import std/tables

# NOTE: jsClean not applied to main handler because of cstring/string boundary
# issue. Functions imported from other modules expect `string`, but jsClean
# rewrites $ and split to return `cstring`. This is a known gap (see RESULTS.md).
import utils
import sanitizers
import svg_placeholder

# ============================================================
# FFI bindings for Web/Cloudflare APIs
# ============================================================

type
  JsResponse {.importjs: "Response".} = ref object
    status: int
    statusText: cstring
    headers: JsObject
    body: JsObject

  JsRequest {.importjs: "Request".} = ref object
    url: cstring
    headers: JsObject

  JsURL {.importjs: "URL".} = ref object
    host: cstring
    pathname: cstring
    searchParams: JsObject

  JsHeaders {.importjs: "Headers".} = ref object

proc newResponse(body: cstring, init: JsObject): JsResponse {.importjs: "new Response(#, #)".}
proc newURL(url: cstring): JsURL {.importjs: "new URL(#)".}
proc newHeaders(init: JsObject): JsHeaders {.importjs: "new Headers(#)".}
proc get(params: JsObject, key: cstring): cstring {.importjs: "#.get(#)".}
proc set(headers: JsObject, key: cstring, value: cstring) {.importjs: "#.set(#, #)".}
proc sort(params: JsObject) {.importjs: "#.sort()".}
proc consoleError(msg: cstring) {.importjs: "console.error(#)".}

# ============================================================
# Main handler
# ============================================================

proc handleEvent(request: JsRequest): Future[JsResponse] {.async.} =
  let url = newURL(request.url)
  url.searchParams.sort()

  let isImageHost = url.host == "images.placeholders.dev".cstring
  let isApiPath = ($url.pathname).startsWith("/api")

  if isImageHost or isApiPath:
    var opts = defaultOptions()
    opts.dataUri = false  # always return unencoded SVG

    let basePath = ($url.pathname).replace("/api", "")
    if basePath != "/":
      let size = basePath.replace("/", "")
      let parts = size.split("x")
      let w = sanitizeNumber(parts[0])
      let h = if parts.len > 1: sanitizeNumber(parts[1]) else: none(float)
      if w.isSome and h.isSome:
        opts.width = int(w.get)
        opts.height = int(h.get)
      elif w.isSome:
        opts.width = int(w.get)
        opts.height = int(w.get)

    # Process query params
    let sp = url.searchParams
    let widthParam = sp.get("width")
    if widthParam != nil:
      let v = sanitizeNumber($widthParam)
      if v.isSome: opts.width = int(v.get)
    let heightParam = sp.get("height")
    if heightParam != nil:
      let v = sanitizeNumber($heightParam)
      if v.isSome: opts.height = int(v.get)
    let textParam = sp.get("text")
    if textParam != nil:
      opts.text = sanitizeString($textParam)
    let fontFamilyParam = sp.get("fontFamily")
    if fontFamilyParam != nil:
      opts.fontFamily = sanitizeStringForCss($fontFamilyParam)
    let bgColorParam = sp.get("bgColor")
    if bgColorParam != nil:
      let v = sanitizeColor($bgColorParam)
      if v.isSome: opts.bgColor = v.get
    let textColorParam = sp.get("textColor")
    if textColorParam != nil:
      let v = sanitizeColor($textColorParam)
      if v.isSome: opts.textColor = v.get

    let svg = simpleSvgPlaceholder(opts)
    let headers = newJsObject()
    headers["content-type"] = "image/svg+xml; charset=utf-8".cstring.toJs
    headers["access-control-allow-origin"] = "*".cstring.toJs
    headers["Cache-Control"] = imageCacheHeader.cstring.toJs
    let init = newJsObject()
    init["headers"] = headers
    return newResponse(svg.cstring, init)

  # Non-image request — return 404
  let init404 = newJsObject()
  init404["status"] = 404.toJs
  return newResponse("Not Found".cstring, init404)

proc fetch(request: JsRequest, env: JsObject): Future[JsResponse] {.async, exportc.} =
  try:
    return await handleEvent(request)
  except:
    consoleError(getCurrentExceptionMsg().cstring)
    let init = newJsObject()
    init["status"] = 500.toJs
    return newResponse("Internal Error".cstring, init)
