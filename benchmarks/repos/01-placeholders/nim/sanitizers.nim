## sanitizers — input validation and sanitization
## Port of: placeholders.dev/src/sanitizers.ts
##
## Note: sanitize-html and validate-color npm deps are replaced with
## inline implementations (strip HTML tags, basic CSS color validation).

import std/strutils
import std/jsre
import std/options
import std/tables

# ============================================================
# Core sanitizers
# ============================================================

proc sanitizeNumber*(input: string): Option[float] =
  let s = input.strip()
  if s.len == 0: return none(float)
  try:
    let n = parseFloat(s)
    return some(n)
  except ValueError:
    return none(float)

proc stripHtmlTags(s: cstring): cstring =
  ## Simple HTML tag stripper (replaces sanitize-html dependency)
  s.replace(newRegExp("<[^>]*>", "g"), "")

proc sanitizeString*(input: string): string =
  var value = $stripHtmlTags(input.cstring)
  value = $cstring(value).replace(newRegExp("""["<>]+""", "g"), "")
  return value

proc sanitizeColor*(input: string): Option[string] =
  ## Basic CSS color validation (replaces validate-color dependency)
  let value = sanitizeString(input)
  # Accept: hex colors, rgb/rgba/hsl/hsla, named colors
  if value.cstring.contains(newRegExp("^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")):
    return some(value)
  if value.cstring.contains(newRegExp("^(rgb|rgba|hsl|hsla)\\(")):
    return some(value)
  # Accept common named colors
  let lower = value.toLowerAscii()
  const namedColors = ["black", "white", "red", "green", "blue", "yellow",
    "cyan", "magenta", "gray", "grey", "orange", "purple", "pink", "brown",
    "transparent", "inherit", "currentcolor"]
  for c in namedColors:
    if lower == c: return some(value)
  return none(string)

proc sanitizeStringForCss*(input: string): string =
  var value = sanitizeString(input)
  value = $cstring(value).replace(newRegExp("[:;]+", "g"), "")
  return value

proc sanitizeBoolean*(input: string): bool =
  let s = input.toLowerAscii()
  return s == "true" or s == "1"

# ============================================================
# Sanitizer map
# ============================================================

type SanitizeKind* = enum
  skNumber, skString, skColor, skCssString, skBoolean

const sanitizerKinds* = {
  "width": skNumber,
  "height": skNumber,
  "text": skString,
  "dy": skNumber,
  "fontFamily": skCssString,
  "fontWeight": skNumber,
  "fontSize": skNumber,
  "bgColor": skColor,
  "textColor": skColor,
  "darkBgColor": skColor,
  "darkTextColor": skColor,
  "textWrap": skBoolean,
}.toTable
