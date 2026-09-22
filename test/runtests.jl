# =============================================================================
# CommonUI test suite — aggregator.
#
#   julia --project=. test/runtests.jl                    # every level
#   julia --project=. test/runtests.jl unit               # one level
#   julia --project=. test/runtests.jl unit integration   # several
# (first time: julia --project=. -e 'using Pkg; Pkg.instantiate()')
#
# Levels run in pyramid order (unit → integration → e2e) whatever order they
# are given in. Every test/<level>/test_*.jl file is included, sorted by name.
# test/manual/ holds live-cluster scripts and is never run from here.
# =============================================================================

const LEVELS = ["unit", "integration", "e2e"]

requested = isempty(ARGS) ? LEVELS : ARGS
unknown = setdiff(requested, LEVELS)
isempty(unknown) || error("Unknown test level(s) $(unknown); expected any of $(LEVELS).")

include(joinpath(@__DIR__, "support", "setup.jl"))

@testset "CommonUI" begin
    for level in filter(in(requested), LEVELS)
        dir = joinpath(@__DIR__, level)
        isdir(dir) || continue
        files = sort(filter(f -> startswith(f, "test_") && endswith(f, ".jl"), readdir(dir)))
        @testset "$level" begin
            for f in files
                include(joinpath(dir, f))
            end
        end
    end
end
