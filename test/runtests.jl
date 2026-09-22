# =============================================================================
# CommonUI test suite
#
# Run with:  julia --project=. test/runtests.jl
# (first time: julia --project=. -e 'using Pkg; Pkg.instantiate()')
#
# Only the pure, network-free utilities (DF_utils, UI_utils) are covered here,
# so this suite runs unattended in CI. SSH_utils talks to a live HPC cluster
# and has its own manual/integration check in test/test_sync.jl (see the
# instructions at the top of that file) — it is not run automatically.
# =============================================================================

using Test
using DataFrames

include(joinpath(@__DIR__, "..", "utils", "DF_utils.jl"))
include(joinpath(@__DIR__, "..", "utils", "UI_utils.jl"))

using .DF_utils
using .UI_utils

@testset "CommonUI" begin

    @testset "DF_utils.generate_dataframe" begin
        # Full-factorial size: number of rows must equal the product of the
        # per-parameter list lengths.
        df = DF_utils.generate_dataframe(["alpha", "beta"], [[0.1, 0.2], [10, 20, 30]])
        @test nrow(df) == 6
        @test Set(names(df)) == Set(["alpha", "beta"])
        @test Set(df.alpha) == Set([0.1, 0.2])
        @test Set(df.beta) == Set([10, 20, 30])
        # Every combination of (alpha, beta) appears exactly once.
        combos = Set(zip(df.alpha, df.beta))
        @test length(combos) == 6

        # Single-parameter, single-value case: one row.
        df1 = DF_utils.generate_dataframe(["x"], [[1.0]])
        @test nrow(df1) == 1

        # An empty value list for any parameter means zero simulations.
        df0 = DF_utils.generate_dataframe(["x", "y"], [[1.0, 2.0], Float64[]])
        @test nrow(df0) == 0

        @test DF_utils.isloaded() === true
    end

    @testset "UI_utils.parse_values" begin
        @test UI_utils.parse_values("1,3,5") == [1.0, 3.0, 5.0]
        @test UI_utils.parse_values("1:5") == collect(1.0:5.0)
        @test UI_utils.parse_values("0:0.5:2") == collect(0.0:0.5:2.0)
        @test UI_utils.parse_values("1,3:5,8") == [1.0, 3.0, 4.0, 5.0, 8.0]
        # Blank entries (extra commas / whitespace) are dropped, not kept as gaps.
        @test UI_utils.parse_values("1, , 2") == [1.0, 2.0]
        # Unparseable tokens pass through as strings rather than erroring.
        @test UI_utils.parse_values("abc") == ["abc"]
    end

    @testset "UI_utils.parse_to_slurm_array" begin
        @test UI_utils.parse_to_slurm_array("1,3,5") == "1,3,5"
        @test UI_utils.parse_to_slurm_array("1:5") == "1-5"
        @test UI_utils.parse_to_slurm_array("1,3:5,8") == "1,3-5,8"
        # "start:step:stop" collapses to SLURM's "start-stop:step" form.
        @test UI_utils.parse_to_slurm_array("1:2:9") == "1-9:2"
    end

end
