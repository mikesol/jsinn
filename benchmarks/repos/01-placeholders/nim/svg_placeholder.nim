## svg_placeholder — generates SVG placeholder images
## Port of: placeholders.dev/src/simple-svg-placeholder.ts

import std/strutils
import std/math
import std/uri
import std/jsre
import utils

type
  PlaceholderOptions* = object
    width*: int
    height*: int
    text*: string
    fontFamily*: string
    fontWeight*: string
    fontSize*: int
    lineHeight*: float
    dy*: float
    bgColor*: string
    textColor*: string
    darkBgColor*: string
    darkTextColor*: string
    dataUri*: bool
    charset*: string
    textWrap*: bool
    padding*: string

proc defaultOptions*(width = 300, height = 150): PlaceholderOptions =
  let fs = int(floor(float(min(width, height)) * 0.2))
  PlaceholderOptions(
    width: width,
    height: height,
    text: $width & "\xC3\x97" & $height,  # × character
    fontFamily: "sans-serif",
    fontWeight: "bold",
    fontSize: fs,
    lineHeight: 1.2,
    dy: float(fs) * 0.35,
    bgColor: "#ddd",
    textColor: "rgba(0,0,0,0.5)",
    darkBgColor: "",
    darkTextColor: "",
    dataUri: true,
    charset: "UTF-8",
    textWrap: false,
    padding: "0.5em",
  )

proc simpleSvgPlaceholder*(opts: PlaceholderOptions): string =
  let safeText = escapeXml(opts.text)
  var content = ""
  var style = ""

  if opts.darkBgColor.len > 0 or opts.darkTextColor.len > 0:
    style = "<style>@media (prefers-color-scheme: dark) {"
    if opts.darkBgColor.len > 0:
      style.add " rect { fill: " & opts.darkBgColor & "; }"
    if opts.darkTextColor.len > 0 and not opts.textWrap:
      style.add " text { fill: " & opts.darkTextColor & "; }"
    if opts.darkTextColor.len > 0 and opts.textWrap:
      style.add " div { color: " & opts.darkTextColor & " !important; }"
    style.add " }</style>"

  if opts.textWrap:
    content = "<foreignObject width=\"" & $opts.width & "\" height=\"" & $opts.height & "\">" &
      "<div xmlns=\"http://www.w3.org/1999/xhtml\" style=\"" &
      "align-items: center; box-sizing: border-box; " &
      "color: " & opts.textColor & "; display: flex; " &
      "font-family: " & opts.fontFamily & "; " &
      "font-size: " & $opts.fontSize & "px; " &
      "font-weight: " & opts.fontWeight & "; " &
      "height: 100%; line-height: " & $opts.lineHeight & "; " &
      "justify-content: center; padding: " & opts.padding & "; " &
      "text-align: center; width: 100%;\">" & safeText & "</div></foreignObject>"
  else:
    content = "<text fill=\"" & opts.textColor & "\" font-family=\"" & opts.fontFamily &
      "\" font-size=\"" & $opts.fontSize & "\" dy=\"" & $opts.dy &
      "\" font-weight=\"" & opts.fontWeight &
      "\" x=\"50%\" y=\"50%\" text-anchor=\"middle\">" & safeText & "</text>"

  var str = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" & $opts.width &
    "\" height=\"" & $opts.height & "\" viewBox=\"0 0 " & $opts.width & " " & $opts.height & "\">" &
    style &
    "<rect fill=\"" & opts.bgColor & "\" width=\"" & $opts.width & "\" height=\"" & $opts.height & "\"/>" &
    content &
    "</svg>"

  # Strip newlines/tabs and condense spaces
  str = $cstring(str).replace(newRegExp("[\\t\\n\\r]", "g"), "")
  str = $cstring(str).replace(newRegExp("\\s\\s+", "g"), " ")

  if opts.dataUri:
    var encoded = encodeUrl(str, usePlus = false)
    encoded = encoded.replace("(", "%28")
    encoded = encoded.replace(")", "%29")
    return "data:image/svg+xml;charset=" & opts.charset & "," & encoded

  return str
