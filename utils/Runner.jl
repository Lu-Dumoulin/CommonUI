# Process-execution seam for SSH_utils. Code that spawns ssh/scp calls
# `capture`/`execute` on a runner instead of `readchomp`/`run` directly, so
# tests can substitute a runner that records commands instead of running them.
module Runner
export AbstractRunner, ShellRunner, capture, execute

abstract type AbstractRunner end

# The real thing: runs the command on this machine.
struct ShellRunner <: AbstractRunner end

capture(::ShellRunner, cmd::Cmd) = readchomp(cmd)   # stdout as a String
execute(::ShellRunner, cmd::Cmd) = run(cmd)         # for side effects; throws if the command fails

# A runner that forgets a method fails loudly here instead of silently
# falling back to the shell.
capture(r::AbstractRunner, ::Cmd) = error("$(typeof(r)) does not implement Runner.capture(::$(typeof(r)), ::Cmd)")
execute(r::AbstractRunner, ::Cmd) = error("$(typeof(r)) does not implement Runner.execute(::$(typeof(r)), ::Cmd)")

end
