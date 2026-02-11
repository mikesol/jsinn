# Benchmark #1: placeholders.dev

**Source**: [Cherry/placeholders.dev](https://github.com/Cherry/placeholders.dev)
**Category hits**: strings, regex, maps/tables, arrays, math, URL/URI, async, error handling

## Metrics

| Metric | Value |
|--------|-------|
| Original TS (ported files) | 379 lines (4 files) |
| Nim source | 379 lines (4 files) |
| Raw JS output | 2,526 lines |
| Post-processed JS output | 2,099 lines |
| **Size ratio** | **5.5x** |
| Target | < 2x |
| **Grade** | **FAIL** |

Note: Original TS total is 518 lines across 6 files, but we skipped `analytics.ts` (Cloudflare-specific) and `types.ts` (5-line type alias). The Nim port covers the same logic in 379 lines.

## What compiled correctly

- FFI bindings to `URL`, `Response`, `Headers`, `RegExp` — clean and correct
- `async`/`await` — `Future[T]` maps to async functions properly
- `std/jsre` — `RegExp` usage in sanitizers compiles to native `new RegExp()`
- `try`/`except` — maps to `try`/`catch` (with Nim exception machinery overhead)
- `std/options` — `Option[T]` works but pulls in `nimCopy` for value semantics
- `std/jsffi` — `JsObject` property access compiles to direct `[]` access

## Bloat breakdown

Total: 2,099 lines. Application logic: ~180 lines. Runtime/stdlib overhead: ~1,920 lines.

### 1. NTI type info tables (lines 1–105, ~105 lines)

Runtime type information nodes used by `nimCopy` for deep copying. Every Nim type that gets passed around generates one of these.

### 2. nimCopy + deep copy infrastructure (lines 106–213, ~108 lines)

`setConstr`, `nimCopy`, `nimCopyAux`, `isFatPointer`. Nim's value semantics require deep copying of objects and sequences. The original TS has zero deep copies — everything is reference semantics.

### 3. String representation layer (lines 215–270, ~56 lines)

`eqStrings`, `makeNimstrLit`, `cstrToNimstr`. Nim strings on JS are `seq[byte]` (integer arrays), not JS strings. Every string literal becomes an integer array: `[60,115,116,121,108,101,62]` instead of `"<style>"`. Every JS↔Nim boundary requires `cstrToNimstr`/`toJSStr` conversion.

### 4. toJSStr and string conversion (lines 340–396, ~57 lines)

Full UTF-8 decoder to convert Nim's `seq[byte]` back to JS strings. Includes `decodeURIComponent` fallback with exception handling.

### 5. Hash table: farm hash (lines 600–812, ~213 lines)

`std/tables` pulls in farm hash (BigInt-based!): `lenU`, `load8e`, `load8`, `rotR`, `len16`, `load4e`, `load4`, `shiftMix`, `len0_16`, `len17_32`, `len33_64`, `weakLen32withSeeds`, `weakLen32withSeeds2`, `hashFarm`. This is for `Table[string, string]` (the `xmlEscapeMap` in utils.nim) and `OrderedTable` (the `addHeaders` constant).

The original TS uses plain `const` objects for both. Zero hash infrastructure.

### 6. Hash table: operations (lines 820–989, ~170 lines)

`hash`, `isFilled`, `nextTry`, `rawGet`, `mustRehash`, `rawInsert`, `enlarge`, `rawGetKnownHC`, `HEX5BHEX5DHEX3D` (the `[]=` operator), `toOrderedTable`, `initOrderedTable`, `nextPowerOfTwo`, `slotsNeeded`.

### 7. String operations (lines 994–1332, ~340 lines)

Without `jsClean`, all `strutils` functions pull in Nim reimplementations:
- `nsuStartsWith` — reimplements `startsWith` byte-by-byte
- `nsuReplaceStr` — reimplements `replace` with Boyer-Moore skip table
- `nsuSplitString` — reimplements `split` with substring search
- `nsuStrip` — reimplements `strip` with char set scanning
- `nsuFindChar`, `nsuFindStrA` — substring search infrastructure
- `substr`, `fill`, `nsuInitSkipTable`, `nsuInitNewSkipTable`
- `nsuToLowerAsciiStr`, `nsuToLowerAsciiChar` — reimplements `toLowerAscii`

The original TS uses `.startsWith()`, `.replace()`, `.split()`, `.trim()`, `.toLowerCase()` — zero custom implementations.

### 8. Float parsing (lines 398–519, ~122 lines)

`nimParseBiggestFloat` — a full float parser reimplemented in JS, used by `sanitizeNumber` via `parseFloat`. The original TS calls native `parseFloat()` directly.

### 9. URI encoding (lines 1816–1917, ~102 lines)

`encodeUrl` reimplements URL encoding character by character with a massive 52+10 case switch statement + hex encoding. The original TS would use `encodeURIComponent()`.

### 10. WangYi hash for char table (lines 1638–1728, ~91 lines)

A second hash implementation (`hashWangYi1` + `hiXorLoJs`) for `Table[char, string]` (the `xmlEscapeMap`). Plus a second set of `rawGet`/`hasKey`/`contains`/`HEX5BHEX5D` functions specialized for char keys.

### 11. Exception/utility infrastructure (~100 lines scattered)

`raiseException`, `reraiseException`, `raiseDefect`, `unhandledException`, `getCurrentException`, `getCurrentExceptionMsg`, `isNimException`, `isObj`, `newSeq`.

## Root causes (prioritized)

### P0: String representation (affects everything)

Nim strings on JS are `seq[byte]`. This single design choice cascades into:
- Every string literal → integer array
- Every JS↔Nim boundary → `cstrToNimstr`/`toJSStr` conversion
- Every string comparison → `eqStrings` (byte-by-byte)
- Every string concat → `push.apply` on arrays

**jsClean** partially fixes this by rewriting `$` and `split` to return `cstring`, but can't be applied to code that calls functions expecting `string` (the cstring/string boundary problem).

### P1: std/tables pulls farm hash (383 lines)

Using `Table[K,V]` or `OrderedTable` for compile-time constants (header maps, escape maps) drags in an entire hash table implementation. The fix is either a macro that emits JS objects/Maps directly, or avoiding `std/tables` in favor of JS-native lookups.

### P2: strutils without jsClean (340 lines)

The `main.nim` handler couldn't use `jsClean` due to the cstring/string boundary issue (wall #2). As a result, `startsWith`, `replace`, `split`, `strip`, `toLowerAscii` all use Nim reimplementations instead of native JS string methods.

### P3: nimCopy + NTI (213 lines)

Nim value semantics trigger deep copies on every assignment. In JS, objects are reference semantics and this entire infrastructure is unnecessary for most cases. `nimCopy` is called ~30 times in the output.

### P4: std/uri encodeUrl (102 lines)

`encodeUrl` reimplements URL encoding. Should map to `encodeURIComponent()`.

### P5: Float parsing (122 lines)

`parseFloat` reimplements float parsing. Should map to native `parseFloat()`.

## Follow-up issues needed

| # | Issue | Lines saved | Priority |
|---|-------|-------------|----------|
| 1 | jsClean cstring/string composability fix | ~340 (enables P2) | P0 |
| 2 | std/tables → JS object/Map shim | ~383 | P1 |
| 3 | String literal encoding (integer arrays → strings) | pervasive | P0 |
| 4 | nimCopy elimination for JS-safe types | ~213 | P1 |
| 5 | std/uri → encodeURIComponent shim | ~102 | P2 |
| 6 | parseFloat → native shim | ~122 | P2 |
| 7 | std/sets → JS Set shim | pulled by tables | P2 |
| 8 | Post-process: strip NTI tables | ~105 | P2 |

## Readability assessment

The application functions (`handleEvent`, `simpleSvgPlaceholder`, `sanitizeColor`, etc.) are **structurally recognizable** but polluted:

```javascript
// What we get:
var isApiPath = nsuStartsWith(cstrToNimstr(url.pathname), [47,97,112,105]);
var basePath = nsuReplaceStr(cstrToNimstr(url.pathname), [47,97,112,105], []);
opts.text = nimCopy(null, sanitizeString(cstrToNimstr(textParam)), NTI33554449);

// What it should be:
var isApiPath = url.pathname.startsWith("/api");
var basePath = url.pathname.replace("/api", "");
opts.text = sanitizeString(textParam);
```

The structure is correct — the logic flow matches the original. But no human would write code this way.
