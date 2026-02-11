# jsinn

Make `nim js` not suck. Clean, readable JavaScript output from idiomatic Nim.

## The problem

Nim's JavaScript backend produces correct but terrible output. Write 22 lines of Nim that upper-cases a string:

```nim
import std/jsffi, std/strutils

proc sanitizeEnvVar(name: string): string =
  result = name.toUpperAscii().replace("-", "_").replace(".", "_")
```

Get 684 lines of JavaScript where `"openai-key"` becomes `[111,112,101,110,97,105,45,107,101,121]` and string operations work on integer arrays.

## What jsinn does

jsinn fixes five things about `nim js` output:

1. **Native JS strings** — `"hello"` stays `"hello"`, not `[104,101,108,108,111]`
2. **Tree shaking** — remove unreachable functions from output
3. **Dead infrastructure elimination** — remove `nimCopy`, NTI tables, and other runtime scaffolding when unused
4. **Stdlib-to-builtin mapping** — `toUpperAscii()` becomes `.toUpperCase()`, `%*{}` becomes `JSON.stringify()`
5. **Cosmetic cleanup** — `const`/`let`, readable parameter names, no `BeforeRet` labels

## Spike results

| Tier | Nim source | `nim js` today | jsinn target |
|------|-----------|----------------|--------------|
| Pure FFI | 15 lines | 481 B (22 lines) | ~400 B (~15 lines) |
| String ops | 22 lines | 18 KB (684 lines) | ~1 KB (~25 lines) |
| Async + JSON | 28 lines | 57 KB (1545 lines) | ~2 KB (~35 lines) |

See `benchmarks/spike/` for the actual Nim source and JS output.

## Validation

jsinn is validated against **20 real-world TypeScript/JavaScript projects**, rewritten in idiomatic Nim. The litmus test: a JS developer who's never seen Nim should be able to read the output, understand it, and modify it.

jsinn ships when 18 of 20 benchmarks pass. See `VISION.md` for full details.

## Status

Early development. The spike proves the opportunity; the work is ahead.

## License

MIT
