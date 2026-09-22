# =============================================================================
# Shared test setup: loads the utility modules once.
#
# Every test file includes this first, so a file works both on its own
# (`julia --project=. test/unit/test_df_utils.jl`) and under test/runtests.jl.
# The isdefined guards make the second and later includes no-ops, so the
# modules are loaded exactly once per process. Test files call the utilities
# fully qualified (`DF_utils.generate_dataframe`) rather than `using` them.
# No tests here.
# =============================================================================

using Test
using DataFrames

isdefined(Main, :DF_utils) || include(joinpath(@__DIR__, "..", "..", "utils", "DF_utils.jl"))
isdefined(Main, :UI_utils) || include(joinpath(@__DIR__, "..", "..", "utils", "UI_utils.jl"))

isdefined(Main, :capture_stdout) || include(joinpath(@__DIR__, "helpers.jl"))
