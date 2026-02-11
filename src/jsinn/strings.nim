## jsinn/strings — Compile-time rewriting of Nim string operations to JS-native FFI
##
## Usage:
##   import jsinn/strings
##   jsClean:
##     proc myProc(...) = ...
##
## The `jsClean` macro walks the AST and rewrites recognized Nim stdlib
## calls to thin {.importjs.} wrappers that produce clean JS output.
## Without this, `nim js` represents strings as char arrays and pulls in
## hundreds of lines of runtime.

import std/macros

# ============================================================
# Shim table: Nim stdlib → JS native
# ============================================================

type ShimDef = object
  nimName: string
  jsName: string
  importjs: string
  params: string
  retType: string

const shimDefs: seq[ShimDef] = @[
  ShimDef(nimName: "toUpperAscii", jsName: "jsToUpper",
          importjs: "#.toUpperCase()",     params: "s: cstring",          retType: "cstring"),
  ShimDef(nimName: "toLowerAscii", jsName: "jsToLower",
          importjs: "#.toLowerCase()",     params: "s: cstring",          retType: "cstring"),
  ShimDef(nimName: "replace",      jsName: "jsReplace",
          importjs: "#.replaceAll(#, #)",  params: "s, a, b: cstring",    retType: "cstring"),
  ShimDef(nimName: "strip",        jsName: "jsTrim",
          importjs: "#.trim()",            params: "s: cstring",          retType: "cstring"),
  ShimDef(nimName: "startsWith",   jsName: "jsStartsWith",
          importjs: "#.startsWith(#)",     params: "s, prefix: cstring",  retType: "bool"),
  ShimDef(nimName: "endsWith",     jsName: "jsEndsWith",
          importjs: "#.endsWith(#)",       params: "s, suffix: cstring",  retType: "bool"),
  ShimDef(nimName: "contains",     jsName: "jsContains",
          importjs: "#.includes(#)",       params: "s, sub: cstring",     retType: "bool"),
  ShimDef(nimName: "find",         jsName: "jsIndexOf",
          importjs: "#.indexOf(#)",        params: "s, sub: cstring",     retType: "int"),
  ShimDef(nimName: "split",        jsName: "jsSplit",
          importjs: "#.split(#)",          params: "s, sep: cstring",     retType: "seq[cstring]"),
  ShimDef(nimName: "repeat",       jsName: "jsRepeat",
          importjs: "#.repeat(#)",         params: "s: cstring, n: int",  retType: "cstring"),
  ShimDef(nimName: "parseInt",     jsName: "jsParseInt",
          importjs: "parseInt(#)",         params: "s: cstring",          retType: "int"),
  ShimDef(nimName: "parseFloat",   jsName: "jsParseFloat",
          importjs: "parseFloat(#)",       params: "s: cstring",          retType: "float"),
]

proc findShim(name: string): int =
  for i, s in shimDefs:
    if s.nimName == name: return i
  return -1

proc shimDecl(s: ShimDef): string =
  "proc " & s.jsName & "(" & s.params & "): " & s.retType &
  " {.importjs: \"" & s.importjs & "\".}"


# ============================================================
# AST rewriter
# ============================================================

proc rewriteAst(n: NimNode, usedShims: var seq[string]): NimNode =
  # --- Named function calls: foo(args...) ---
  if n.kind == nnkCall and n[0].kind == nnkIdent:
    let idx = findShim(n[0].strVal)
    if idx >= 0:
      let shim = shimDefs[idx]
      if shim.nimName notin usedShims:
        usedShims.add shim.nimName
      result = newCall(ident(shim.jsName))
      for i in 1..<n.len:
        result.add rewriteAst(n[i], usedShims)
      return

  # --- Method call syntax: obj.method(args...) ---
  if n.kind == nnkCall and n[0].kind == nnkDotExpr:
    let methodName = n[0][1].strVal
    let idx = findShim(methodName)
    if idx >= 0:
      let shim = shimDefs[idx]
      if shim.nimName notin usedShims:
        usedShims.add shim.nimName
      result = newCall(ident(shim.jsName))
      # obj becomes first argument
      result.add rewriteAst(n[0][0], usedShims)
      for i in 1..<n.len:
        result.add rewriteAst(n[i], usedShims)
      return

  # --- Bare method syntax: obj.method (no parens) ---
  if n.kind == nnkDotExpr and n.len == 2 and n[1].kind == nnkIdent:
    let idx = findShim(n[1].strVal)
    if idx >= 0:
      let shim = shimDefs[idx]
      if shim.nimName notin usedShims:
        usedShims.add shim.nimName
      result = newCall(ident(shim.jsName))
      result.add rewriteAst(n[0], usedShims)
      return

  # --- $ prefix → String() ---
  if n.kind == nnkPrefix and n[0].kind == nnkIdent and n[0].strVal == "$":
    if "toString" notin usedShims:
      usedShims.add "toString"
    var arg = rewriteAst(n[1], usedShims)
    if arg.kind == nnkPar and arg.len == 1:
      arg = arg[0]
    return newCall(ident"jsStr", arg)

  # --- & infix → (# + #) ---
  if n.kind == nnkInfix and n[0].kind == nnkIdent and n[0].strVal == "&":
    if "concat" notin usedShims:
      usedShims.add "concat"
    return newCall(ident"jsConcat",
      rewriteAst(n[1], usedShims),
      rewriteAst(n[2], usedShims))

  # --- Leaf node ---
  if n.len == 0:
    return n

  # --- Default: recurse ---
  result = copyNimNode(n)
  for i in 0..<n.len:
    result.add rewriteAst(n[i], usedShims)


# ============================================================
# Shim declaration generation
# ============================================================

proc generateShimProcs(usedShims: seq[string]): NimNode =
  result = newStmtList()
  for name in usedShims:
    case name
    of "toString":
      result.add parseStmt("proc jsStr(x: int): cstring {.importjs: \"String(#)\".}")
      result.add parseStmt("proc jsStr(x: float): cstring {.importjs: \"String(#)\".}")
      result.add parseStmt("proc jsStr(x: cstring): cstring {.importjs: \"String(#)\".}")
      result.add parseStmt("proc jsStr(x: bool): cstring {.importjs: \"String(#)\".}")
    of "concat":
      result.add parseStmt("proc jsConcat(a, b: cstring): cstring {.importjs: \"(# + #)\".}")
    else:
      let idx = findShim(name)
      if idx >= 0:
        result.add parseStmt(shimDecl(shimDefs[idx]))


# ============================================================
# Public macro
# ============================================================

macro jsClean*(body: untyped): untyped =
  ## Rewrites Nim stdlib string/math calls to JS-native FFI equivalents.
  ##
  ## Usage:
  ##   jsClean:
  ##     proc myProc(s: string): string =
  ##       result = s.toUpperAscii().replace("-", "_")
  ##
  ## This rewrites toUpperAscii → .toUpperCase() and replace → .replaceAll()
  ## via {.importjs.} shims, so jsgen emits clean JS instead of pulling in
  ## the Nim string runtime.
  var usedShims: seq[string]
  let rewritten = rewriteAst(body, usedShims)

  result = newStmtList()
  # Emit shim declarations first
  result.add generateShimProcs(usedShims)
  # Then the rewritten user code
  result.add rewritten
