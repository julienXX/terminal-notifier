# Modernization report: `terminal-notifier` Ruby gem

Scope: the Ruby gem under `Ruby/` (the native macOS app under `Terminal
Notifier/` is untouched). Target: Ruby 4.0.6, the current release.

## TL;DR

- The old dev dependencies (`bacon`, `mocha`, `mocha-on-bacon`) don't run on
  Ruby 4.0.6 at all — `bundle install` failed outright. They're gone,
  replaced with RSpec + rspec-mocks (no separate mocking gem needed) and
  SimpleCov.
- 100% line and branch coverage (up from 0%, since the old suite couldn't
  execute on the target Ruby).
- `bundler-audit` reports no vulnerabilities. RuboCop reports no offenses.
- One functional refactor: the executable's argument-handling logic was
  extracted from `bin/terminal-notifier` into `TerminalNotifier::CLI` so it
  can be unit-tested; behavior is unchanged.

## Dependency changes

| Gem | Before | After |
|---|---|---|
| `bacon` | ~1.1 (dev) | removed |
| `mocha` | ~0.11 (dev) | removed |
| `mocha-on-bacon` | ~0.2 (dev) | removed |
| `rspec` | — | `~> 3.13` (dev) |
| `simplecov` | — | `~> 0.22` (dev) |
| `rubocop` | — | `~> 1.75` (dev) |
| `rubocop-rake` | — | `~> 0.7` (dev) |
| `rubocop-rspec` | — | `~> 3.5` (dev) |
| `bundler-audit` | — | `~> 0.9` (dev) |
| `rake` | unpinned | `~> 13.0` (dev) |

`bacon`/`mocha`/`mocha-on-bacon` are effectively unmaintained (no releases in
years) and, more importantly, `bacon` no longer installs cleanly against
current Ruby/RubyGems — running `bundle install` on Ruby 4.0.6 against the
original `Gemfile.lock` fails immediately with `Bundler::GemNotFound`. RSpec
is the de facto standard replacement and ships its own mocking library
(`rspec-mocks`), so there was no need to find a `mocha` substitute — one
fewer dependency overall.

Development dependencies moved from `gem.add_development_dependency` in the
gemspec into a `group :development, :test do ... end` block in the
`Gemfile`, per current RuboCop/community convention
(`Gemspec/DevelopmentDependencies`) — it keeps the released gem's
`.gemspec` free of anything not needed by consumers.

No runtime dependencies exist (the gem only uses Ruby stdlib:
`shellwords`, `rbconfig`, `English`, `time`), so there was nothing to
replace on that front.

## Security

- Ran `bundle exec bundler-audit check --update` against the resolved
  `Gemfile.lock`: **no vulnerabilities found**.
- No use of `eval`, `system`/backtick-with-interpolated-untrusted-input, or
  other injection-prone constructs. The one place that shells out
  (`TerminalNotifier.execute`) passes an **array** to `IO.popen`, so
  arguments are never re-interpreted by a shell — this was already correct
  in the original code and preserved as-is.

## Compatibility fixes for Ruby 4.0.6

- **`RUBY_VERSION < '1.9'` dead branch removed** from `execute` (dropped the
  now-impossible-to-reach `Shellwords.join` fallback and the associated
  string-command code path — `IO.popen` always receives an array now,
  which was already the modern/safe branch).
- **`frozen_string_literal: true`** added to every Ruby file; the one place
  that mutated a string literal in place (`result = ''; result << output`)
  now uses `result = +''` to opt that one string back out of freezing.
- **`STDOUT`/`STDERR` → `$stdout`/`$stderr`**: the global-variable forms
  respect test/output redirection (`RSpec::Matchers#output`), the constants
  don't. This was required to make `execute`'s verbose/error-path output
  testable at all, and is also RuboCop's (`Style/GlobalStdStream`)
  preferred form.
- **`$? and $?.success?` → `require 'English'; $CHILD_STATUS&.success?`**:
  same behavior, clearer name, safe navigation instead of a double
  existence check.
- Manual string slicing modernized (`v[1..-1]` → `v[1..]`,
  `output.split("\n")[1..-1]` → `[1..]`), `Hash#inject` → `each_with_object`
  for the `list` parser (identical behavior, avoids an unnecessary block
  return value).
- `gem.required_ruby_version = '>= 3.2'` added to the gemspec. Nothing in
  this gem actually requires syntax newer than that (no pattern matching,
  no `it` block-arg shorthand, etc.), so the floor reflects genuinely
  supported versions rather than an arbitrary "match the CI box" pin. CI's
  matrix (`3.2`, `3.3`, `3.4`, `4.0.6`) verifies the floor and the ceiling
  both work.
- `.ruby-version` pinned to `4.0.6` for local development.

## Refactor: extracted `TerminalNotifier::CLI`

`bin/terminal-notifier` previously contained its own argument-assembly
logic (read a message from stdin when piped and `-message` wasn't given,
then `exec` into the vendored binary) inline, ending in a real `exec` call
that replaces the process. That's untestable in-process by construction.

The logic moved to `TerminalNotifier::CLI.run(argv = ARGV, stdin = STDIN)`
in `lib/terminal-notifier/cli.rb`, and `bin/terminal-notifier` is now a
2-line dispatch shim:

```ruby
require 'terminal-notifier/cli'
TerminalNotifier::CLI.run if __FILE__ == $PROGRAM_NAME
```

`CLI.run` is fully unit-tested (all three argv/stdin combinations). The
2-line shim itself is intentionally excluded from the coverage requirement
— see "Coverage" below for why.

## Coverage

- **Before**: unmeasurable / effectively 0%. The original suite (`bacon`
  + `mocha` + `mocha-on-bacon`) cannot even install on Ruby 4.0.6, so
  `rake spec` never ran.
- **After**: **100% line, 100% branch** (52/52 lines, 22/22 branches),
  enforced by `SimpleCov.minimum_coverage line: 100, branch: 100` — the
  suite fails the build if either drops.
- 37 examples across `spec/terminal_notifier_spec.rb` (library) and
  `spec/cli_spec.rb` (CLI + bin script).
- One deliberate, documented exclusion: `bin/terminal-notifier` itself
  (the 2-line shim above) is filtered out of SimpleCov's accounting.
  Reason: Ruby's `Coverage` module does not accumulate line/branch hits
  across repeated in-process `load`s of the *same* file path — only the
  last `load`'s execution counts survive at report time. Since exercising
  both the "run as `$0`" and "merely required" branches of that guard
  requires two separate `load`s of the same path in the same process, one
  of the two always reads back as 0% regardless of what actually ran. This
  is a genuine coverage-tooling limitation, not untested code — both
  scenarios are exercised by `spec/cli_spec.rb`'s two examples, and all of
  the actual logic (the interesting part) lives in the fully-covered `CLI`
  module.
- One pre-existing behavior worth flagging in review: `notify_result`
  returns **`true`** (not `false`) for an empty result — it's
  `result.length == 0 || result.downcase...` in the original code (now
  `result.empty? || ...` post-cleanup), so an empty string short-circuits
  the `||` to the boolean `true`, not a symbol. This looked at first like
  a bug but is faithfully preserved and now has a test
  (`returns true for an empty result instead of symbolising it`)
  pinning it down, since changing public-API return values wasn't in scope
  here.

## Lint

- Added `.rubocop.yml` (`NewCops: enable`, `TargetRubyVersion: 3.2`) with
  `rubocop-rake` and `rubocop-rspec` plugins.
- `bundle exec rubocop`: **0 offenses** across all 9 inspected files
  (including `bin/terminal-notifier`, picked up automatically via its
  shebang).
- A few cops are deliberately disabled/scoped, each with an inline
  rationale comment in `.rubocop.yml`:
  - `Style/OptionalBooleanParameter` and `Naming/PredicateMethod` — the
    public API (`notify`, `remove`, `list`) has long-standing positional
    boolean args (`verbose`, `always_string`) and a `remove` method that
    returns a boolean without a `?` suffix; both are load-bearing for
    existing callers, so this pass left the *signatures* alone and fixed
    everything cop-flagged that didn't require an API break.
  - `Naming/FileName` for `lib/terminal-notifier.rb` — the dash in the
    filename is required to match `require 'terminal-notifier'` and the
    gem's RubyGems name.
  - `RSpec/MultipleDescribes`, `RSpec/DescribeClass` (scoped to
    `spec/cli_spec.rb`) and `RSpec/MessageSpies` — style preferences that
    didn't fit this file's shape (one file documents both a module and a
    script's entry-point behavior; a negative `not_to receive` expectation
    has no clearer spy-based equivalent).

## CI

Added `.github/workflows/ruby.yml`: runs `rspec`, `rubocop`, and
`bundler-audit` on a matrix of Ruby `3.2`, `3.3`, `3.4`, and `4.0.6` on
`ubuntu-latest`. The test suite is platform-independent by design (all
macOS-specific behavior is exercised through stubs), so Linux runners are
sufficient for CI even though the tool itself only *runs* on macOS.

## Documentation

- Every public method and the `TerminalNotifier` module gained YARD-style
  `@param`/`@return` docs (most bodies/examples were already documented in
  prose; this pass added the structured tags plus docs for previously
  undocumented pieces: `BIN_PATH`, `UnsupportedPlatformError`,
  `available?`, `version`, `execute`, and the new `CLI` module).
- `Ruby/README.markdown` gained a "Requirements" note (Ruby 3.2+) and a
  "Development" section describing how to run the test suite, RuboCop, and
  bundler-audit locally.

## Not changed / explicitly out of scope

- The native Objective-C app (`Terminal Notifier/`) and Xcode project are
  untouched — this pass is scoped to the Ruby gem.
- No public method signatures or return-value semantics changed (see the
  `notify_result` empty-string note above).
