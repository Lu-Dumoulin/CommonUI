# CommonUI — testability refactor and test pyramid

Plan of record for making this repository testable and giving it a real test
pyramid. Written after a read-through of the whole repo on 2026-09-22.
Conventions live in `CLAUDE.md`; this document is the *what* and *why*.

**Scope: CommonUI only.** HydraFluids is a separate, larger job (see
[Out of scope](#out-of-scope)).

---

## 0. State of the working tree

Before starting, know what is already here:

- Branch **`chore/test-pyramid-and-architecture`** is checked out (created for
  this work, nothing committed to it yet).
- **Uncommitted, from an earlier session:** `LICENSE`, `Project.toml`,
  `test/runtests.jl`, `test/test_sync.jl`, modified `.gitignore` and a rewritten
  `README.md`. These are a good starting point — fold them into the first
  commits rather than discarding them.
- **`README.md` carries a CI badge pointing at `.github/workflows/CI.yml`, which
  does not exist.** CI is deliberately out of scope for now, so **remove the
  badge** rather than leave it broken.
- `.git/_stale_locks_to_delete/` holds a handful of empty `*.lock` files left by
  a sandboxed git that could not clean up after itself. Delete that folder;
  nothing depends on it.

---

## 1. Why the code cannot be tested today

| # | Problem | Principle | Consequence |
|---|---|---|---|
| 1 | Every `SSH_utils` function calls `readchomp`/`run` on a real `ssh`/`scp` at the point of use. There is no seam. | DIP | Nothing in the 318-line module can be tested without a cluster, so none of it is tested. |
| 2 | `sync` lists the remote tree, parses it, decides what is stale, creates directories, downloads in parallel *and* prints progress. | SRP | The staleness decision — the only subtle logic in the file — is unreachable from a test. |
| 3 | The Slurm batch script, the array spec, the partition string, the GPU constraint string and the cluster paths are built inline in Pluto cells of `RunSimulations.pluto.jl`. | SRP, DRY | Business logic inside a notebook cell can never be tested, and the `"all"` check and the `/srv/beegfs/...` path layout are each written more than once. |
| 4 | `generate_dataframe` builds the full-factorial sweep with hand-rolled block arithmetic (`count`, `div(nsim, count)`, modular indexing). | KISS | Correct, but nobody can read it and be sure; the row ordering it produces is a hard contract (row *i* ↔ `SLURM_ARRAY_TASK_ID` *i*). |
| 5 | `parse_values` and `parse_to_slurm_array` each re-implement "split on commas, then interpret `a:b` / `a:b:c`". | DRY | Two copies of one rule; a fix to one silently skips the other. |
| 6 | `print_list` decides emptiness, prints to stdout and returns Markdown. | SRP | The formatting cannot be asserted on. |
| 7 | `test/` is flat, unit-only, and `test_sync.jl` is a live-cluster script sitting next to the automated tests. | — | No pyramid; a stray `julia test/test_sync.jl` hits the real cluster. |

Invariants 4 and the exact `ssh`/`scp` argument vectors are the two places where
a careless refactor would break real work. Both get characterisation tests
**before** anything is touched.

---

## 2. Target layout

```
utils/
  Runner.jl          NEW  process-execution seam (AbstractRunner, ShellRunner)
  SSH_commands.jl    NEW  pure: command construction, find-output parsing, sync planning
  SSH_utils.jl       REWRITTEN as a thin execution layer; public API unchanged
  Slurm_utils.jl     NEW  pure: array spec, partition, GPU constraint, paths, batch script
  DF_utils.jl        simplified
  UI_utils.jl        shared tokenizer; formatting split from printing
test/
  runtests.jl        aggregator, level filter via ARGS
  coverage.jl        dependency-free coverage report + lcov.info
  support/
    setup.jl         loads the modules once (works standalone or under runtests)
    FakeRunner.jl    recording test double implementing the Runner interface
    FakeCluster.jl   writes stub ssh/scp executables + a local "cluster" directory
  unit/              test_df_utils.jl, test_ui_utils.jl, test_ssh_commands.jl,
                     test_slurm_utils.jl, test_runner.jl
  integration/       test_ssh_utils.jl, test_sync.jl
  e2e/               test_workflow.jl
  manual/            test_sync_live.jl   (the current test/test_sync.jl, moved)
docs/
  REFACTORING_PLAN.md
CLAUDE.md
.vscode/tasks.json   NEW  "Run tests" / "Run tests with coverage"
```

`SSH_utils.jl` includes `Runner.jl` and `SSH_commands.jl` **inside** its own
module (`include` resolves relative to the including file, so this works in
Pluto too). Tests reach them as `SSH_utils.Runner` and `SSH_utils.SSH_commands`
— one copy, no module-name collisions with anything the notebook loads.

---

## 3. Module designs

### 3.1 `Runner.jl` — the seam

```julia
abstract type AbstractRunner end
struct ShellRunner <: AbstractRunner end

capture(::ShellRunner, cmd::Cmd) = readchomp(cmd)   # stdout as String
execute(::ShellRunner, cmd::Cmd) = run(cmd)         # side effect; throws on failure
```

Plus fallbacks on `AbstractRunner` that `error(...)` naming the missing method,
so a half-written runner fails loudly instead of silently reaching the shell.

Every `SSH_utils` function gains `; runner = ShellRunner()`. Defaults mean the
notebook is untouched; tests pass a `FakeRunner`.

### 3.2 `SSH_commands.jl` — pure

No I/O except read-only filesystem queries (`isfile`, `mtime`) in `plan_sync`.

```julia
remote_target(usr, hst)                        # "usr@hst"
ssh_cmd(opts::Cmd, usr, hst, remote_cmd)       # `ssh $opts usr@hst <cmd>`
scp_down_cmd(opts, usr, hst, remote, local)    # `scp $opts -r usr@hst:remote local`
scp_up_cmd(opts, usr, hst, remote, local)      # `scp $opts -r local usr@hst:remote`
scp_up_file_cmd(opts, usr, hst, remote, local) # same, no -r
controlmaster_opts(dir, persist)               # the -o ControlMaster=... Cmd
control_exit_cmd(opts, usr, hst)               # `ssh $opts -O exit usr@hst`
find_mtimes_cmd(root)                          # "find <root> -type f -printf '%T@\\t%P\\n'"
find_sizes_cmd(root)                           # "find <root> -type f -printf '%s\\t%P\\n'"
ensure_trailing_slash(path)
parse_find_listing(raw::AbstractString, ::Type{T})  # -> Vector{Tuple{T,String}}
plan_sync(entries, local_dir)                  # -> (to_download::Vector{String}, n_skipped::Int)
is_unsafe_remote_path(path)                    # the rm_dir guard, as a predicate
```

Note for whoever implements this: `up` and `up_dir` currently build **identical**
commands (the `"""..."""` quoting around the local path in `up_dir` has no effect
inside a `Cmd` literal — interpolated values never word-split). Implement both on
one builder and keep `up_dir` as a documented alias for API compatibility.

The `\\t` / `\\n` in the `find` commands must stay double-backslashed in the
Julia source: `find` itself interprets them, not Julia.

### 3.3 `SSH_utils.jl` — thin layer

Same exported names, same positional arguments, same printed output. Each
function now: build a command via `SSH_commands`, hand it to the runner, do the
Julia-side bookkeeping.

`SSH_OPTS::Ref{Cmd}` stays as the notebook-facing default (toggled by
`ssh_open`/`ssh_close`), but every function takes `; opts = SSH_OPTS[]` so tests
are hermetic and never depend on global state left by another test.

`sync` becomes: `capture` the `find` listing → `parse_find_listing` →
`plan_sync` → `mkpath` → parallel `execute` of the downloads → print. Each step
independently testable.

Drop the unused `using RemoteFiles, OpenSSH_jll` from the module (the notebook
loads them itself). That removes two dependencies from the test environment.

### 3.4 `Slurm_utils.jl` — pure, extracted from the notebook

```julia
wants_all(s)                                    # occursin("all") || occursin("All")
all_array_spec(nsim; max_concurrent = 40)       # "1-<nsim>%40"
array_spec(s, nsim, range_parser; max_concurrent = 40)
selected_indices(s, nsim, value_parser)         # -> Vector{Int}; "" -> [1]
gpu_feature(name)                               # "H100" -> "nvidia_h100_nvl", ...
gpu_constraint(names)                           # join(..., "|")
partition_spec(private, use_shared_gpu)         # "<private>,shared-gpu" when shared
cluster_home_path(user)                         # "/home/users/<initial>/<user>"
cluster_scratch_path(user)                      # "/srv/beegfs/scratch/users/<initial>/<user>"
batch_script(; array, partition, time, constraint, username,
               data_path, code_path, mem = 3000, gpus = 1)
local_run_command(; gpu, main_path = "../sim/main.jl")
```

`range_parser` and `value_parser` are injected (`UI_utils.parse_to_slurm_array`
and `UI_utils.parse_values` in the notebook). `Slurm_utils` therefore has **no
dependencies at all** — it is the easiest module in the repo to test, which is
the point.

`gpu_feature` keeps the current fallback: anything that is not `"H100"` or
`"A100-40Gb"` maps to `nvidia_a100_80gb_pcie`.

### 3.5 `DF_utils.jl`

Replace the block arithmetic with the implementation that states the intent:

```julia
rows = vec(collect(Iterators.product(listtab...)))   # first parameter varies fastest
DataFrame([name => [row[i] for row in rows] for (i, name) in enumerate(listname)])
```

**This is order-equivalent to the current code** — verified by hand for
`(["alpha","beta"], [[0.1,0.2],[10,20,30]])`, which yields
`(0.1,10) (0.2,10) (0.1,20) (0.2,20) (0.1,30) (0.2,30)`. Column element types
come out at least as concrete as before. Preserve the two edge behaviours:
an empty value list for any parameter returns a bare `DataFrame()` (zero rows
*and* zero columns), and a length-1 list contributes a constant column.

Pin this with a characterisation test **before** touching the function.

### 3.6 `UI_utils.jl`

- Extract the shared tokenizer: split on commas, drop blanks, then per token
  decide plain value vs `a:b` vs `a:b:c`. `parse_values` and
  `parse_to_slurm_array` both build on it.
- Keep the quirks — they are relied on: `parse_values` returns `Float64` for
  numbers and passes unparseable tokens through as `String`;
  `parse_to_slurm_array` silently *drops* tokens that are not integers, and
  renders `"1:2:9"` as `"1-9:2"`.
- Split `print_list` into `format_list(names, values) -> String` (testable),
  `empty_field_alert()` and the existing `print_list` wrapper that keeps the
  notebook's behaviour.
- `@named_parse` stays as is; add tests for the `_str` stripping and the error
  on a non-vector argument.

---

## 4. Test inventory

### Unit — `test/unit/`

**`test_df_utils.jl`**
- full-factorial row count equals the product of list lengths
- **row ordering** — asserts the exact 6-row sequence above (characterisation)
- first parameter varies fastest, last varies slowest
- length-1 parameter becomes a constant column
- empty parameter list yields an empty frame
- column names follow `listname`, in order
- mismatched `listname`/`listtab` lengths raise

**`test_ui_utils.jl`**
- `parse_values`: plain list, `a:b`, `a:b:c`, mixed, blanks dropped,
  unparseable token passes through as a String, empty string yields empty
- `parse_to_slurm_array`: plain list, `a:b` → `a-b`, `a:b:c` → `a-c:b`,
  mixed, non-integer tokens dropped, empty string yields `""`
- `format_list`: name/value pairs, and the alert path when a field is empty
- `@named_parse`: strips `_str`, keeps non-`_str` values, errors on a bare symbol

**`test_ssh_commands.jl`** — the argument vectors, asserted exactly
- `ssh_cmd` produces `["ssh", "user@host", "<cmd>"]` with no opts, and splices
  opts in when present
- `scp_down_cmd` / `scp_up_cmd` place `-r` and the `user@host:` prefix on the
  right side; `scp_up_file_cmd` omits `-r`
- the remote path and the local path are single arguments even with spaces
- `find_mtimes_cmd` / `find_sizes_cmd` contain literal `\t` and `\n`
- `ensure_trailing_slash` is idempotent
- `parse_find_listing` skips malformed lines and unparseable numbers
- `plan_sync` against a temp dir: missing locally → download; older locally →
  download; newer locally → skip; counts add up
- `is_unsafe_remote_path` true for `""`, `"/"`, `"~"`, `"~/"`, `"/home"`,
  `"/home/"` and whitespace-padded forms; false for a normal scratch path

**`test_slurm_utils.jl`**
- `wants_all` for `"all"`, `"All"`, embedded, and false for `"1,2"`
- `all_array_spec(12)` → `"1-12%40"`, honours `max_concurrent`
- `array_spec` delegates to the injected parser when not "all"
- `selected_indices`: `""` → `[1]`, `"all"` → `1:nsim`, `"1,3:5"` → `[1,3,4,5]`
- `gpu_feature` for each enum value and the fallback
- `gpu_constraint`: single, multiple joined with `|`, empty → `""`
- `partition_spec` with and without shared GPU
- `cluster_home_path` / `cluster_scratch_path` use the username's first letter
- **`batch_script` golden test** — the whole generated script compared against a
  fixture string, so the Slurm header can never drift unnoticed
- `local_run_command`: `-t auto` present on CPU, absent on GPU

**`test_runner.jl`**
- `ShellRunner` captures stdout from a trivial command (`echo`) — the one place
  a unit test may spawn a process, because that *is* the unit under test
- a runner implementing neither method errors with a message naming it

### Integration — `test/integration/`

Real subprocesses, stub `ssh`/`scp`, no network. Skipped on Windows.

**`test_ssh_utils.jl`**
- `ssh` returns the stub's stdout; `squeue` passes `--me` by default
- `mkdir` creates the remote directory and is idempotent, printing the
  "exists" branch the second time
- `up_file` / `up_dir` land files in the fake cluster tree
- `down` retrieves a file
- `readdir` lists the fake cluster directory
- `rm_dir` refuses each unsafe path **without invoking ssh at all** (assert the
  fake runner recorded nothing), and removes a normal path
- `ssh_open` sets `SSH_OPTS`, those options appear in the next command, and
  `ssh_close` clears them again

**`test_sync.jl`**
- fresh sync into an empty directory downloads every file and rebuilds the
  subdirectory structure
- an immediate second sync downloads nothing
- touching one remote file causes exactly that one to be re-downloaded
- `nparallel = 1` and `nparallel = 4` give identical results
- `check_download_sizes` reports a truncated local file and a missing one

### E2E — `test/e2e/test_workflow.jl`

One test, the whole offline workflow, asserting at each stage:

1. UI strings (`"0:0.5:2"`, `"10,20"`) → `parse_values` → `generate_dataframe`
   → write `DF.csv`
2. read `DF.csv` back, `nsim` matches the sweep size
3. `"all"` → `array_spec` → `"1-6%40"`; `"1,3:5"` → `selected_indices`
4. `batch_script` → written as `Project.sh`, contains that array spec and the
   scratch path built from the username
5. `mkdir` + `up_file` the script and `DF.csv` into the fake cluster
6. results appear "on the cluster"; `sync` pulls them down
7. `check_download_sizes` reports nothing bad

That chain is what a user actually does, and it exercises all four modules
together without a cluster.

### Manual — `test/manual/test_sync_live.jl`

The existing `test/test_sync.jl`, moved and renamed, header updated to say it is
manual and never part of `runtests.jl`. Its dependency preamble can shrink once
`SSH_utils` no longer imports `RemoteFiles`/`OpenSSH_jll`.

---

## 5. The fake-cluster harness

`test/support/FakeCluster.jl` is the piece that makes integration and E2E
testing possible. It writes two stub executables into a temp directory and
prepends that directory to `PATH` for the duration of a test:

- **`ssh`** — ignores options and the `user@host` argument, takes the last
  argument as the remote command and `eval`s it locally. Because the "cluster"
  is just a temp directory, remote absolute paths are real local paths and need
  no rewriting. It must emulate GNU `find -printf '%T@\t%P\n'` and
  `'%s\t%P\n'`, since **macOS `find` has no `-printf`** — detect those two
  invocations and reproduce them with `find` + `stat` (`stat -f` on BSD,
  `stat -c` on GNU).
- **`scp`** — strips a `user@host:` prefix from whichever side has it and does
  a `cp`/`cp -R`.

Both are short POSIX shell scripts, `chmod`ed to `0o755`. Use
`withenv("PATH" => stubdir * ":" * ENV["PATH"]) do ... end` so the stubs are
only visible inside the test, and `mktempdir()` so everything is cleaned up.

Guard the whole harness with `Sys.iswindows() && return` (report as skipped).

This gives real coverage of the `run`/`readchomp` code paths — argument quoting,
exit codes, parallel `scp` — that a `FakeRunner` alone cannot reach. The
`FakeRunner` in `test/support/FakeRunner.jl` is still worth having for unit-level
assertions about *which* commands were issued and for the "refused, so nothing
ran" cases.

---

## 6. Coverage tooling

`test/coverage.jl`, no dependencies:

1. Re-run the suite in a subprocess with `--code-coverage=user`.
2. Parse the resulting `utils/*.jl.*.cov` files — each line is `count` or `-`
   (not executable) followed by the source line.
3. Print a per-file table (covered / coverable / percent) and the uncovered line
   numbers, then a total.
4. Write `lcov.info` (the `SF:` / `DA:` / `end_of_record` subset is enough) so
   the VS Code *Coverage Gutters* extension colours the gutter directly.

Add `*.cov`, `*.jl.*.cov`, `lcov.info` and `coverage/` to `.gitignore`.

Aim for meaningful coverage of `utils/`, excluding the notebooks — they are not
covered by this suite and pretending otherwise would be dishonest.

---

## 7. Commit sequence

Each commit leaves the suite green.

1. `chore: add LICENSE, project environment and editor tasks`
   (folds in the uncommitted `LICENSE`/`Project.toml`, `.gitignore` additions,
   `.vscode/tasks.json`, `CLAUDE.md`, this plan)
2. `test: restructure the suite into a pyramid` — directories, `runtests.jl`
   aggregator with level filtering, `support/setup.jl`, move `test_sync.jl` to
   `manual/test_sync_live.jl`
3. `test: pin current DF_utils and UI_utils behaviour` — characterisation only,
   no source changes
4. `refactor: build the parameter sweep with Iterators.product`
5. `refactor: share one tokenizer between the UI parsers`
6. `feat: add the command-runner seam` — `Runner.jl` + `test_runner.jl`
7. `refactor: extract pure command construction from SSH_utils` —
   `SSH_commands.jl`, `SSH_utils` rewritten on top of it, `test_ssh_commands.jl`
8. `test: exercise SSH_utils against a stub cluster` — `FakeCluster.jl`,
   `integration/`
9. `feat: extract Slurm job configuration from the notebook` — `Slurm_utils.jl`
   + golden test
10. `refactor: build the batch script from Slurm_utils in the notebook` —
    the single Pluto cell edit; keep it last so it can be dropped on its own
11. `test: add the offline end-to-end workflow test`
12. `chore: add coverage reporting`
13. `docs: document the test pyramid and drop the stale CI badge`

Step 10 is the only one that touches a notebook. Re-open
`RunSimulations.pluto.jl` in Pluto afterwards and confirm the generated script
still matches the golden fixture before committing.

---

## 8. Invariants — do not change these without saying so

- Row order of `generate_dataframe`: first parameter varies fastest. Row *i* of
  `DF.csv` is `SLURM_ARRAY_TASK_ID` *i*; changing the order silently remaps
  every previously generated sweep.
- The exact `ssh`/`scp` argument vectors, including where `-r` appears.
- `SSH_OPTS` empty by default — no multiplexing until `ssh_open` is called, and
  never on Windows.
- `rm_dir`'s refusal list and its error message.
- The generated Slurm header: `--output=%J.out`, `--mem=3000`, `--gpus=1`, and
  `export use_gpu=true` before `mkdir -p $path_to_data`.
- `parse_values` returning `Vector{Any}` with strings passed through — the
  notebook relies on `Number.(...)` failing loudly on bad input.

---

## Out of scope

- **CI.** Explicitly deferred. Remove the stale badge; do not add a workflow.
- **HydraFluids.** Its `src/sim` reads `ENV["SLURM_ARRAY_TASK_ID"]`,
  `ENV["use_gpu"]` and `DF.csv` at include time and defines ~30 `const` globals
  the kernels close over, so `include`ing any file starts a simulation and
  nothing can be unit-tested. Fixing that means a parameter struct, separating
  the pure physics from the time loop and I/O, and a regression test pinning
  current numerical output first. Separate piece of work.
- **Turning CommonUI into a Julia package.** Tempting, and more conventional,
  but it changes how HydraFluids consumes this repo. Revisit once the tests
  exist.
