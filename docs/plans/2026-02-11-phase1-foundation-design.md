# Phase 1: Foundation — Issue Design

**Date**: 2026-02-11
**Phase**: Phase 1: Foundation
**Goal**: Prove the two-layer approach (macro library + optional post-processing) works on the spike benchmarks.

## Architecture

jsinn is two user-space layers, zero compiler modifications:

1. **Macro library** (compile-time): Intercepts Nim stdlib calls in the AST and rewrites them to JS-native FFI equivalents before jsgen runs. This prevents jsgen from triggering the char array / Nim runtime machinery.
2. **Post-processing** (after codegen, if needed): Existing tools (esbuild, Terser, Closure Compiler) for tree shaking and dead code elimination. Only used if the macro layer doesn't eliminate enough dead weight on its own.

## Issues

### Issue #1: Macro library — strutils rewrite

**Scope**: Write a Nim macro that intercepts `strutils` calls and rewrites them to JS-native FFI equivalents using `cstring` and `{.importjs.}` wrappers.

**Functions to cover** (used in spike Tier 2):
- `toUpperAscii(s: string): string` → `s.cstring.toUpperCase()` via importjs
- `replace(s, sub, by: string): string` → `s.cstring.replace(sub, by)` via importjs (note: JS `replace` only replaces first occurrence by default — need `replaceAll` or regex)
- `&` (string concatenation) → ensure it flows through cstring `+` rather than char array `.concat()`

**Key design decisions**:
- The macro should be opt-in: `import jsinn/strings` or similar. It doesn't modify behavior globally.
- String literals that flow through the macro should remain as JS string literals, not char arrays.
- The macro must handle `string` ↔ `cstring` boundaries gracefully. Nim's `string` and `cstring` are different types; the macro needs to manage conversions.

**Acceptance criteria**:
- Tier 2 spike (`worker_strings.nim`), when compiled with the jsinn macro, produces `nim js` output where:
  - `"openai-key"` appears as a string literal, not `[111,112,101,110,97,105,45,107,101,121]`
  - `toUpperAscii` becomes `.toUpperCase()` or equivalent JS builtin
  - `replace` becomes `.replace()` or `.replaceAll()` JS builtin
  - No `nsuToUpperAsciiStr`, `nsuReplaceStr`, or other strutils runtime functions in output

**Not in scope**:
- Full strutils coverage (Phase 2)
- Post-processing or cosmetic cleanup
- Tier 3 spike (that's Issue #2)

---

### Issue #2: Macro library — json rewrite

**Scope**: Write a Nim macro that intercepts `json` module calls and rewrites them to JS-native FFI equivalents.

**Functions to cover** (used in spike Tier 3):
- `%*{...}` (json construction) → JS object literal
- `$jsonNode` (json serialization) → `JSON.stringify()`
- `jsonNode.to(T)` or field access → direct property access

**Key design decisions**:
- `%*{"ok": true, "url": url}` should compile to something like `{ok: true, url: url}` in JS, not a `JsonNode` tree that gets serialized.
- This interacts with Issue #1 because Tier 3 also uses strutils. Both macros must compose.

**Acceptance criteria**:
- Tier 3 spike (`worker_async.nim`), when compiled with both jsinn macros, produces `nim js` output where:
  - JSON construction uses JS object literals or `JSON.stringify`, not Nim's `JsonNode` tree
  - No `toUgly`, `HEX25__pureZjson` or other json module runtime functions in output
  - async/await maps cleanly (it already does via `asyncjs` — just verify no extra bloat)
  - `strutils` operations also clean (from Issue #1 macro)

**Not in scope**:
- JSON parsing (`parseJson`) — only construction/serialization for now
- Full json module coverage (Phase 2)
- Post-processing or cosmetic cleanup

---

### Issue #3: Evaluate post-processing needs + spike validation

**Scope**: After Issues #1 and #2 are complete, compile all three spike tiers with macros applied. Inspect the raw output. Determine whether post-processing is needed and what tool to use.

**Steps**:
1. Compile all 3 spike tiers with jsinn macros applied
2. Measure output: line count, byte count, readability
3. Compare against target files in `benchmarks/spike/output/*.target.js`
4. If dead weight remains (NTI tables, nimCopy, unused functions):
   - Test esbuild, Terser, or Closure Compiler on the output
   - Pick the one that produces the cleanest result with least config
   - Document the tool choice and configuration
5. If no dead weight remains: document that post-processing is unnecessary
6. File follow-up issues for anything that remains (cosmetics, parameter names, etc.)

**Acceptance criteria (Phase 1 exit gate)**:
- Tier 1: output ≤ 20 lines (currently 22 — minor cleanup)
- Tier 2: output < 40 lines (currently 684)
- Tier 3: output < 60 lines (currently 1545)
- All string literals remain as string literals
- A JS developer can read the output and understand what it does

**Not in scope**:
- Building a custom post-processing tool (use existing)
- Cosmetic perfection (Phase 2/3 territory)
- The 20-repo benchmark (Phase 3)

## Dependency chain

```
#1 (strutils macro) ─┐
                      ├──→ #3 (evaluate + validate)
#2 (json macro) ──────┘
```

Issues #1 and #2 are parallelizable. Issue #3 is blocked by both.
