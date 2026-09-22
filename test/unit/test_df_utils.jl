include(joinpath(@__DIR__, "..", "support", "setup.jl"))

@testset "DF_utils" begin

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

end
