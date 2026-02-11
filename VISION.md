# jsinn — Vision 0.1.0

*Make `nim js` not suck. Clean, readable JavaScript output from idiomatic Nim.*

*Arabic jinn: a hidden force that transforms things. Your Nim goes in, clean JS comes out.*

---

## 1. The Problem

Nim has a JavaScript backend. It produces correct output. It also produces *terrible* output.

Write 22 lines of Nim that upper-cases a string and builds a JSON response. The Nim compiler emits 684 lines of JavaScript — 18 KB — where `"openai-key"` becomes `[111,112,101,110,97,105,45,107,101,121]` and string concatenation operates on integer arrays. Add async/await and JSON and you get 1,545 lines — 57 KB — of completely unreadable code.

This isn't a niche concern. It means:

- **You can't eject.** If you build on `nim js` and later want to maintain the JS directly, you're handed an opaque blob. There's no path from Nim to "I'll take it from here in JS."
- **You can't debug.** Source maps help, but the underlying JS is structurally alien. When something goes wrong at the JS level, you're reading machine code.
- **You can't deploy lean.** A Cloudflare Worker has size limits. 57 KB for a 28-line handler is not acceptable.
- **You can't hire.** No JS developer will maintain code where strings are integer arrays.

The Nim community's answer is "use a minifier." That addresses bundle size but not readability. Minified garbage is still garbage — just smaller garbage.

---

## 2. The Thesis

The Nim JS backend (`compiler/jsgen.nim`) is 3,232 lines. It's not a monster. The problem isn't complexity — it's that the backend faithfully translates *all* of Nim's semantics to JavaScript, including semantics that JavaScript already handles natively. Strings become byte arrays because Nim strings are byte sequences. Deep-copy infrastructure ships because Nim has value semantics. Type metadata tables emit because Nim has RTTI. None of this is necessary when the target is JavaScript and the developer is writing JS-shaped code.

**jsinn fixes five things:**

1. **Native JS strings.** When targeting JS, `string` compiles to JS `string`, not `Array<number>`. `toUpperAscii()` becomes `.toUpperCase()`. String literals stay as string literals. This is the single highest-impact change.

2. **Tree shaking.** Post-codegen pass that removes unreachable functions. Today, importing one module pulls in its entire dependency tree and every exported proc gets codegen'd, even if nothing calls it.

3. **Dead infrastructure elimination.** `nimCopy` (deep-copy for value semantics) and NTI tables (runtime type info) are emitted for every program, even when no code path uses them. If your program uses `ref` types (which it should, for JS), this infrastructure is dead weight.

4. **Stdlib-to-builtin mapping.** Nim's stdlib reimplements operations that JavaScript provides natively: `strutils.toUpperAscii` → `String.prototype.toUpperCase`, `json.%*{}` → object literals or `JSON.stringify`, `tables.Table` → `Map` or plain objects. jsinn maps these at the codegen level so the Nim stdlib compiles to idiomatic JS builtins.

5. **Cosmetic cleanup.** Remove `BeforeRet` label patterns, use `const`/`let` instead of `var`, clean up parameter name mangling (`request_p0` → `request`), remove dead variable declarations.

---

## 3. What Success Looks Like

Success is measured by a concrete benchmark: **20 real-world TypeScript/JavaScript projects**, rewritten in idiomatic Nim, compiled through jsinn, producing output that a JavaScript developer can read, understand, and modify as if they wrote it.

The messier the original projects, the better. We want to stress-test against real-world patterns, not toy examples.

### Spike results (baseline)

| Tier | Nim | `nim js` today | jsinn target | Hand-written JS |
|------|-----|----------------|--------------|-----------------|
| 1: Pure FFI | 15 lines | 481 B (22 lines) | ~400 B (~15 lines) | ~10 lines |
| 2: String ops | 22 lines | 18 KB (684 lines) | ~1 KB (~25 lines) | ~15 lines |
| 3: Async + JSON | 28 lines | 57 KB (1545 lines) | ~2 KB (~35 lines) | ~25 lines |

### The litmus test

A developer who has never seen Nim should be able to read jsinn's output, understand what it does, and modify it. Not "figure it out with effort" — **read it like they wrote it**.

### Quantitative targets

- Output size within **3x** of equivalent hand-written JS (by line count)
- Output size within **5x** of equivalent hand-written JS (by byte count)
- Zero Nim runtime functions in output when the program doesn't need them
- All string literals remain as string literals, never as integer arrays

---

## 4. Approach

jsinn operates as a **post-processing layer** on top of `nim js` output, plus targeted patches to `compiler/jsgen.nim` where post-processing alone isn't sufficient (primarily: native string representation).

### 4.1 What changes in the compiler

The native string representation is the one change that cannot be done as post-processing. When `jsgen.nim` decides to represent `"hello"` as `[104,101,108,108,111]`, that decision propagates through every string operation. Fixing this requires modifying the string codegen path in jsgen to emit JS string literals and JS string methods instead of byte array operations.

This is bounded work. The relevant code paths in jsgen are:
- String literal emission
- String concatenation
- String comparison
- String indexing (which changes semantics — byte index vs character index)

The string indexing semantic difference is the one genuinely hard part. Nim strings are byte sequences; JS strings are UTF-16. Code that indexes into strings by byte offset will behave differently. jsinn handles this by:
- Defaulting to JS native strings (correct for the vast majority of code)
- Providing a `{.byteString.}` pragma for code that genuinely needs byte-level access
- Emitting a compile-time warning when byte-indexed string access is detected

### 4.2 What changes as post-processing

Everything else can be done as a post-codegen pass over the emitted JS:

- **Tree shaking**: Build a call graph from the emitted JS, remove unreachable functions
- **Dead infrastructure elimination**: Detect unused `nimCopy`, NTI tables, `setConstr`, and remove them
- **Stdlib-to-builtin rewriting**: Pattern-match known Nim stdlib codegen patterns and replace with JS builtins (e.g., the `nsuToUpperAsciiStr` function → `.toUpperCase()` call)
- **Cosmetic cleanup**: `var` → `const`/`let`, parameter demangling, BeforeRet elimination, dead variable removal

### 4.3 What doesn't change

- The Nim compiler itself (beyond the string representation patch in 4.1)
- Nim's macro system, type system, or semantics
- How developers write Nim code — jsinn is transparent
- Correctness — jsinn output must be semantically identical to `nim js` output for all inputs

---

## 5. The 20-Repo Benchmark

The benchmark suite validates jsinn against real-world code patterns. Each benchmark consists of:

1. **An original TypeScript/JavaScript project** (or representative subset)
2. **A Nim port** written in idiomatic Nim (not "Nim that avoids Nim features")
3. **jsinn output** from compiling the Nim port
4. **A readability score**: can a JS developer understand the output without knowing Nim?

### Selection criteria for benchmark repos

- Variety: CLI tools, API servers, browser apps, utility libraries, Workers
- Messiness: real-world code with edge cases, not textbook examples
- Feature coverage: strings, JSON, async/await, classes, error handling, closures, modules
- Size range: from 50-line utilities to 500+ line applications

### Benchmark grading

For each benchmark, three metrics:

1. **Size ratio**: jsinn output bytes / hand-written JS bytes (target: < 3x)
2. **Line ratio**: jsinn output lines / hand-written JS lines (target: < 3x)
3. **Readability**: blind review by a JS developer (pass/fail: "could you maintain this?")

A benchmark passes if all three metrics are met. jsinn ships when **18 of 20 benchmarks pass**.

---

## 6. Non-Goals

- **Full Nim compatibility.** jsinn targets Nim code that is JS-shaped — uses ref types, avoids low-level byte manipulation, doesn't depend on Nim's specific string encoding. Code that needs Nim's exact byte-level string semantics should use standard `nim js`.
- **Minification.** jsinn produces readable code, not minimal code. Use Terser/Closure Compiler on top if you want minification.
- **Source maps.** jsinn output should be readable enough that source maps are a nice-to-have, not a necessity. Source map support may come later but is not a priority.
- **Non-JS targets.** jsinn is about JavaScript. If you want WASM, use Nim's C backend + Emscripten.
- **Forking the compiler.** jsinn aims to be upstreamable. The jsgen patches should be small, clean, and acceptable to the Nim core team. The post-processing layer is a standalone tool.

---

## 7. Build Order

### Phase 1: Foundation

Prove the approach works on the spike benchmarks.

1. Native JS string representation in jsgen (the compiler patch)
2. Post-processing pass: tree shaking + dead infrastructure elimination
3. Validate: Tier 2 spike drops from 684 lines to < 40 lines
4. Validate: Tier 3 spike drops from 1545 lines to < 60 lines

### Phase 2: Stdlib Mapping

Map the most-used stdlib modules to JS builtins.

1. `strutils` → JS string methods
2. `json` → JSON.parse / JSON.stringify / object literals
3. `tables` → Map or plain objects
4. `sequtils` → Array methods (map, filter, reduce)
5. `asyncjs` → native async/await (already close, needs cleanup)
6. `math` → Math.* (already mapped on JS, needs cleanup)

### Phase 3: Cosmetics

Make the output look like a human wrote it.

1. `var` → `const`/`let` (analyze reassignment)
2. Parameter demangling (`request_p0` → `request`)
3. BeforeRet label elimination → early returns
4. Dead variable elimination
5. Whitespace and formatting normalization

### Phase 4: Benchmark Suite

Build and validate against 20 real-world repos.

1. Select 20 repos (diverse, messy, real)
2. Port representative subsets to idiomatic Nim
3. Compile through jsinn, compare output
4. Iterate on failures until 18/20 pass
5. Write up results

### Phase 5: Community

Ship it.

1. Upstream the jsgen string patch to nim-lang/Nim (PR or RFC)
2. Publish the post-processing tool as a nimble package
3. Write a blog post with benchmark results
4. Present to the Nim community

---

## 8. Relationship to Unanim

jsinn was born from the [Unanim](https://github.com/mikesol/unanim) project, which generates Cloudflare Workers and client applications from Nim source. Unanim needs clean JS output for ejectability — users must be able to take generated artifacts and maintain them independently.

jsinn is a standalone project. Unanim depends on jsinn, but jsinn has no dependency on or knowledge of Unanim. If Unanim dies, jsinn lives. If jsinn succeeds, every Nim project targeting JavaScript benefits.
