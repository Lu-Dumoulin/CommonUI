include(joinpath(@__DIR__, "..", "support", "setup.jl"))

@testset "UI_utils" begin

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
