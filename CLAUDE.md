# CommonUI — working agreement

Conventions for this repository. Read `docs/REFACTORING_PLAN.md` for the current
piece of work and its target design.

## What this repo is

A set of Pluto notebooks plus three Julia utility modules that drive simulation
workflows (parameter sweeps → local/Slurm execution → result download →
visualisation). It is **not a Julia package**: a parent project (HydraFluids)
clones it into `src/CommonUI/`, and the notebooks load the utilities with
`include("utils/X.jl")`, not `import CommonUI`. `Project.toml` is a plain
environment pinning what the utilities and the test suite need.

Keep it that way unless explicitly asked. Converting to a package would change
how every parent project consumes this repo.

## Guardrails — things that break other people's work

1. **The public API of `DF_utils`, `UI_utils` and `SSH_utils` is a contract.**
   `RunSimulations.pluto.jl` and `DataVisualisation.pluto.jl` here, and
   `GenInputParams.pluto.jl` in HydraFluids, call these by name. Function names,
   positional arguments and return types stay as they are. Adding *keyword*
   arguments with defaults is fine and is the preferred way to open a seam for
   testing.

2. **`*.pluto.jl` files are machine-managed.** Never touch the `# ╔═╡ <uuid>`
   cell markers, the `# ╔═╡ Cell order:` block at the bottom, or the Project/
   Manifest blocks. Editing the *body* of an existing cell is safe. Adding or
   removing a cell means editing the order block too — avoid it unless asked,
   and re-open the notebook in Pluto afterwards to confirm it still loads.

3. **Tests never touch the network or a real cluster.** `SSH_utils` talks to
   Baobab; the automated suite must run offline on a laptop with no SSH keys.
   Live-cluster checks live in `test/manual/` and are never run by
   `test/runtests.jl`.

4. **Windows must keep working.** SSH connection multiplexing (`ControlMaster`)
   is macOS/Linux only; the code already degrades to one login per call on
   Windows. Tests that shell out to POSIX stubs must be skipped there, not
   allowed to fail.

5. **No new dependencies without a reason.** The utilities load inside Pluto on
   other people's machines; every dependency is a download they pay for. The
   coverage tooling in particular is deliberately dependency-free.

## Principles, as they apply here

Generic definitions are not useful. These are the specific readings:

- **SRP** — a function either *decides* something or *performs* an effect, not
  both. `sync` currently lists a remote tree, parses it, decides what is stale,
  creates directories, downloads in parallel and prints progress. The deciding
  part is where the bugs are and the only part worth unit-testing, so it gets
  its own pure function.
- **DIP** — code that spawns `ssh`/`scp` depends on a runner interface, not on
  `run`/`readchomp` directly. That single seam is what makes the whole SSH layer
  testable without a cluster.
- **DRY** — the comma/range tokenizer is shared by `parse_values` and
  `parse_to_slurm_array`; the `"all"` check and the cluster path layout
  (`/srv/beegfs/scratch/users/<initial>/<user>`) are each defined once.
  Duplication of *knowledge* is the problem, not duplication of characters.
- **KISS** — prefer the obvious implementation. `generate_dataframe`'s
  hand-rolled block arithmetic is replaced by `Iterators.product`, which says
  what it means. Do not introduce abstraction that has one implementation and
  no test double.
- **Composition root** — the notebook wires modules together. `Slurm_utils`
  does not reach into `UI_utils`; the notebook passes the parser in. Modules
  stay independently loadable and independently testable.

## Test pyramid

```
test/
  runtests.jl        # aggregator: unit → integration → e2e
  support/           # shared helpers and test doubles (no tests here)
  unit/              # many, milliseconds, pure functions, no subprocess
  integration/       # a few, real subprocesses against stub ssh/scp on PATH
  e2e/               # one or two, the whole offline workflow
  manual/            # live-cluster scripts, never run automatically
```

Rules of thumb:

- A test that spawns a process is **not** a unit test — move it down a level.
- Unit tests must not create files outside `mktempdir()`.
- The whole automated suite should stay under ~30 seconds.
- Every new bug fix starts with a failing test that reproduces it.

## AAA

Every `@testset` body is three labelled blocks, in this order, with a blank line
between them:

```julia
@testset "parse_values expands an inclusive range" begin
    # Arrange
    input = "0:0.5:2"

    # Act
    result = UI_utils.parse_values(input)

    # Assert
    @test result == [0.0, 0.5, 1.0, 1.5, 2.0]
end
```

One behaviour per testset, and the name says the behaviour, not the function
("returns the rows in DF.csv order", not "test generate_dataframe"). Shared
setup goes in `test/support/`, never in a `const` at the top of a test file.

## TDD loop

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'   # first time only
julia --project=. test/runtests.jl                    # whole suite
julia --project=. test/runtests.jl unit               # one level
julia --project=. test/unit/test_ui_utils.jl          # one file
```

Order of work, without exception when changing existing behaviour:

1. **Characterise first.** Before refactoring anything that already works, write
   tests that pin its *current* behaviour and watch them pass. That is the only
   safety net here — there is no CI.
2. Red: write the failing test for the new behaviour.
3. Green: the smallest change that passes.
4. Refactor with the suite green.

## Coverage

```bash
julia --project=. test/coverage.jl
```

Prints a per-file percentage and the uncovered line numbers, and writes
`lcov.info` for the VS Code *Coverage Gutters* extension. Coverage is a
conversation starter, not a target: an uncovered line in `utils/` is either a
missing test or code nobody needs. Do not add tests that only touch lines
without asserting behaviour.

## Commits

Conventional Commits, one concern per commit, imperative mood:

```
test: pin current generate_dataframe row ordering
refactor: build the sweep with Iterators.product
feat: add injectable command runner to SSH_utils
```

Tests and the implementation they cover belong in the same commit, except for
characterisation tests, which land first on their own so the diff shows the
behaviour was preserved. End commit messages with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Never push or open a PR unless asked.

## Environment

Julia ≥ 1.10. Always work inside the project environment (`julia --project=.`),
never in the global one.
