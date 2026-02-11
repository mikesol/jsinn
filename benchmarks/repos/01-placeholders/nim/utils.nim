## utils — security headers, caching constants, XML escaping, static file detection
## Port of: placeholders.dev/src/utils.ts

import std/jsffi
import std/strutils
import std/tables
import std/sets

# ============================================================
# Security headers
# ============================================================

let addHeaders* = {
  "X-XSS-Protection": "1; mode=block",
  "X-Frame-Options": "DENY",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer-when-downgrade",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "Feature-Policy": "geolocation 'none'; midi 'none'; sync-xhr 'none'; microphone 'none'; camera 'none'; magnetometer 'none'; gyroscope 'none'; speaker 'none'; fullscreen 'none'; payment 'none';",
  "Content-Security-Policy": "default-src 'self'; script-src 'self' cdnjs.cloudflare.com static.cloudflareinsights.com; style-src 'self' cdnjs.cloudflare.com 'unsafe-inline' fonts.googleapis.com; img-src 'self' data: images.placeholders.dev; child-src 'none'; font-src 'self' fonts.gstatic.com cdnjs.cloudflare.com; connect-src 'self'; prefetch-src 'none'; object-src 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests;",
}.toOrderedTable

# ============================================================
# Caching
# ============================================================

const cacheTtl* = 60 * 60 * 24 * 90  # 90 days
let imageCacheHeader* = "public, max-age=" & $cacheTtl
let errorCacheHeader* = "public, max-age=300"

# ============================================================
# Static file detection
# ============================================================

const staticFileExtensions = [
  "ac3", "avi", "bmp", "br", "bz2", "css", "cue", "dat", "doc", "docx",
  "dts", "eot", "exe", "flv", "gif", "gz", "htm", "html", "ico", "img",
  "iso", "jpeg", "jpg", "js", "json", "map", "mkv", "mp3", "mp4", "mpeg",
  "mpg", "ogg", "pdf", "png", "ppt", "pptx", "qt", "rar", "rm", "svg",
  "swf", "tar", "tgz", "ttf", "txt", "wav", "webp", "webm", "webmanifest",
  "woff", "woff2", "xls", "xlsx", "xml", "zip",
].toHashSet

proc isStaticFile*(pathname: string): bool =
  let lastDot = pathname.rfind('.')
  if lastDot == -1: return false
  let ext = pathname[lastDot + 1 .. ^1].toLowerAscii()
  return ext in staticFileExtensions

# ============================================================
# Available image options
# ============================================================

const availableImageOptions* = [
  "width", "height", "text", "dy", "fontFamily", "fontWeight",
  "fontSize", "bgColor", "textColor", "darkBgColor", "darkTextColor", "textWrap",
]

# ============================================================
# XML escaping
# ============================================================

const xmlEscapeMap = {
  '&': "&amp;",
  '<': "&lt;",
  '>': "&gt;",
  '\'': "&apos;",
  '"': "&quot;",
}.toTable

proc escapeXml*(s: string): string =
  result = ""
  for ch in s:
    if ch in xmlEscapeMap:
      result.add xmlEscapeMap[ch]
    else:
      result.add ch
