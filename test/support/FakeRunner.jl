# =============================================================================
# Test doubles for the SSH_utils.Runner interface. No tests here.
# =============================================================================

# Implements neither `capture` nor `execute`, to check that the interface
# fails loudly instead of falling back to the shell.
struct IncompleteRunner <: SSH_utils.Runner.AbstractRunner end

# Records every command instead of running it. `capture` returns
# `reply(cmd)` (default: ""), so a test can script what the "cluster" says.
struct FakeRunner <: SSH_utils.Runner.AbstractRunner
    reply::Function
    calls::Vector{Cmd}
end
FakeRunner(reply::Function = cmd -> "") = FakeRunner(reply, Cmd[])
FakeRunner(reply::AbstractString) = FakeRunner(cmd -> String(reply))

SSH_utils.Runner.capture(r::FakeRunner, cmd::Cmd) = (push!(r.calls, cmd); r.reply(cmd))
SSH_utils.Runner.execute(r::FakeRunner, cmd::Cmd) = (push!(r.calls, cmd); nothing)

# The argument vectors of every recorded call.
recorded(r::FakeRunner) = [c.exec for c in r.calls]
