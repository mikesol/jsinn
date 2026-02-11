# jsinn — Vision 0.2.0

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

4. **Stdlib-to-builtin mapping.** Nim's stdlib reimplements operations that JavaScript provides natively: `strutils.toUpperAscii` → `String.prototype.toUpperCase`, `json.%*{}` → object literals or `JSON.stringify`, `tables.Table` → `Map` or plain objects. jsinn rewrites these at the macro layer (before jsgen runs) so the Nim stdlib compiles to idiomatic JS builtins.

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

jsinn is **two user-space layers** — a compile-time macro library and a post-codegen processing tool. Neither modifies the Nim compiler. Both ship as standard nimble packages.

### 4.1 Macro library (compile-time, before jsgen)

Nim's macro system runs *before* the JS backend. At the macro layer, code is still a typed Nim AST — strings are `string` type, not char arrays. Char arrays only appear when `jsgen.nim` translates `string` to its JS representation.

jsinn intercepts stdlib calls at the macro layer and rewrites them to JS-native FFI equivalents:

```nim
# What the developer writes:
name.toUpperAscii().replace("-", "_")

# What jsinn's macro rewrites it to (before jsgen sees it):
($name.cstring.toUpperCase()).replace("-".cstring, "_".cstring)
```

Where `toUpperCase` and `replace` are thin `{.importjs.}` wrappers around JS builtins. jsgen sees `cstring` + FFI calls and emits clean JS. The char array machinery never triggers.

This is the key insight: **we don't need to fix jsgen because we can prevent the problem before jsgen runs.** The macro layer is exactly the right intervention point — it's user-space, it's extensible, and it leverages Nim's own metaprogramming facilities.

The macro library covers:
- **String operations**: `strutils` functions → JS `String.prototype` methods
- **JSON construction**: `json.%*{}` → JS object literals / `JSON.stringify`
- **Collection operations**: `sequtils` functions → JS `Array.prototype` methods
- **String representation**: Ensure strings flow through as `cstring` (JS native) rather than Nim `string` (byte array) wherever possible

### 4.2 Post-processing tool (after jsgen)

Even with macro rewrites, `nim js` output still contains dead weight that the macros can't prevent — jsgen unconditionally emits runtime infrastructure. The post-processing tool cleans this up:

- **Tree shaking**: Build a call graph from the emitted JS, remove unreachable functions
- **Dead infrastructure elimination**: Detect unused `nimCopy`, NTI tables, `setConstr`, and remove them
- **Cosmetic cleanup**: `var` → `const`/`let`, parameter demangling (`request_p0` → `request`), BeforeRet elimination, dead variable removal

### 4.3 What doesn't change

- The Nim compiler — zero patches to jsgen or any other compiler file
- Nim's type system or semantics
- How developers write Nim code — jsinn is transparent (you `import jsinn` and your output gets clean)
- Correctness — jsinn output must be semantically identical to `nim js` output for all inputs

---

## 5. The Benchmark Suite

The benchmark suite validates jsinn against real-world code patterns. Each benchmark consists of:

1. **An original TypeScript/JavaScript project** (or representative subset)
2. **A Nim port** written in idiomatic Nim (not "Nim that avoids Nim features")
3. **jsinn output** from compiling the Nim port
4. **A readability score**: can a JS developer understand the output without knowing Nim?

### Coverage matrix

The benchmark repos must collectively exercise **all 13 pattern categories**. Each category must appear in at least 2 repos, and each repo will exercise multiple categories. The goal is uncomfortable coverage — we want to discover what breaks, not confirm what works.

**Core language patterns (must be covered by multiple repos):**

| # | Category | Nim stdlib | JS target | Example patterns |
|---|----------|-----------|-----------|-----------------|
| 1 | String manipulation | `strutils` | `String.prototype` | split, join, replace, trim, case conversion, interpolation, slice, pad |
| 2 | JSON handling | `json` | `JSON.*`, object literals | parse, stringify, nested objects, arrays, dynamic key construction |
| 3 | Array/seq operations | `sequtils` | `Array.prototype` | map, filter, reduce, find, sort, concat, spread, destructuring |
| 4 | Async/await | `asyncjs` | native async/await | fetch chains, Promise.all, error handling in async, sequential vs parallel |
| 5 | Error handling | exceptions | try/catch/throw | custom error types, error propagation, finally blocks, nested try/catch |
| 6 | Closures & callbacks | procs/lambdas | functions/arrows | higher-order functions, event handlers, partial application, currying |
| 7 | Objects & classes | object types | classes/prototypes | methods, inheritance, getters/setters, static members, factory patterns |

**API surface patterns (must be covered):**

| # | Category | Nim stdlib | JS target | Example patterns |
|---|----------|-----------|-----------|-----------------|
| 8 | HTTP fetch | `httpclient`/FFI | `fetch` API | request/response, headers, body parsing, status codes, streaming |
| 9 | URL parsing | `uri` | `URL` API | parse, construct, query params, path manipulation, relative resolution |
| 10 | Key-value maps | `tables` | `Map`/plain objects | get/set/delete, iteration, merging, default values, nested maps |
| 11 | Math operations | `math` | `Math.*` | floor/ceil/round, min/max, random, trig, pow, clamp |
| 12 | Date/time | `times` | `Date`/`Intl` | parsing, formatting, arithmetic, comparison, timezones, ISO 8601 |
| 13 | Regular expressions | `re`/`nre` | `RegExp` | match, replace, capture groups, global/multiline flags, split by regex |

### Selection criteria for benchmark repos

- **Variety**: Cloudflare Workers, API servers, CLI tools, browser utilities, string/data libraries, middleware
- **Messiness**: Real-world code with edge cases, not textbook examples. The messier the better.
- **Size range**: From 50-line single-function utilities to 500+ line applications
- **Overlap**: Each repo should exercise 3-5 categories. Prefer too much overlap over gaps.
- **Source**: Real GitHub repos with real users, not contrived examples

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
- **Modifying the compiler.** jsinn operates entirely in user-space: a macro library (before jsgen) and a post-processing tool (after jsgen). Zero compiler patches. This makes jsinn compatible with any Nim version and eliminates the upstream-acceptance bottleneck.

---

## 7. Build Order

### Phase 1: Foundation

Prove both layers work on the spike benchmarks.

1. Macro library: rewrite `strutils` calls (toUpperAscii, replace) to JS-native FFI equivalents
2. Macro library: rewrite `json` construction (`%*{}`) to JS-native FFI equivalents
3. Post-processing tool: tree shaking + dead infrastructure elimination (nimCopy, NTI tables, unused functions)
4. Post-processing tool: cosmetic cleanup (BeforeRet elimination, var → const/let, parameter demangling)
5. Validate: Tier 2 spike drops from 684 lines to < 40 lines
6. Validate: Tier 3 spike drops from 1545 lines to < 60 lines

### Phase 2: Benchmark-Driven Stdlib Expansion

Port real repos, hit walls, add shims. The benchmark suite and stdlib coverage grow together.

1. Pick a real TypeScript/JavaScript repo from GitHub
2. Port it (or a representative subset) to idiomatic Nim
3. Compile through jsinn (`jsClean` macro + `postprocess.mjs`)
4. Compare output to original — identify what's broken or ugly
5. Add the missing macro shims / post-processing rules to fix it
6. Record the benchmark result
7. Repeat until 20 repos pass (18/20 required for Phase 3)

Stdlib modules get expanded on-demand as repos reveal gaps. No speculative shim work.

### Phase 3: Community

Ship it.

1. Publish both layers as nimble packages
2. Write a blog post with benchmark results
3. Present to the Nim community

---

## 8. Relationship to Unanim

jsinn was born from the [Unanim](https://github.com/mikesol/unanim) project, which generates Cloudflare Workers and client applications from Nim source. Unanim needs clean JS output for ejectability — users must be able to take generated artifacts and maintain them independently.

jsinn is a standalone project. Unanim depends on jsinn, but jsinn has no dependency on or knowledge of Unanim. If Unanim dies, jsinn lives. If jsinn succeeds, every Nim project targeting JavaScript benefits.
