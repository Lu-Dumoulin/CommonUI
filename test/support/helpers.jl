# =============================================================================
# Shared test helpers and fixtures. No tests here.
# =============================================================================

"""
    capture_stdout(f) -> (result, output::String)

Call `f()` with stdout redirected to a temporary file and return its result
together with everything it printed.
"""
function capture_stdout(f)
    mktemp() do path, io
        result = redirect_stdout(f, io)
        flush(io)
        return result, read(path, String)
    end
end

"""
    two_parameter_sweep() -> (listname, listtab)

The reference sweep from docs/REFACTORING_PLAN.md §3.5: two values of
`alpha` crossed with three values of `beta`, six simulations in total.
"""
two_parameter_sweep() = (["alpha", "beta"], [[0.1, 0.2], [10, 20, 30]])
