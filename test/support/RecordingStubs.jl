# =============================================================================
# Recording stubs for `ssh` and `scp`. No tests here.
#
# `record_commands(f; reply)` puts stub `ssh`/`scp` executables first on PATH,
# runs `f()`, and returns every call they received as a vector of argument
# vectors (program name first), plus whatever `f` returned and printed. The
# `ssh` stub prints `reply` to stdout; `scp` prints nothing and copies
# nothing. POSIX only: callers skip on Windows.
# =============================================================================

const _STUB_SCRIPT = raw"""
#!/bin/sh
# Concurrent calls (sync's parallel scp) must not interleave their records,
# so each append holds a lock; mkdir is atomic on every POSIX filesystem.
out="CALL $(basename "$0")"
for a in "$@"; do
out="$out
ARG $a"
done
while ! mkdir "$STUB_LOG.lock" 2>/dev/null; do sleep 0.01; done
printf '%s\n' "$out" >> "$STUB_LOG"
rmdir "$STUB_LOG.lock"
if [ "$(basename "$0")" = "ssh" ]; then cat "$STUB_REPLY"; fi
"""

function _parse_stub_log(path)
    calls = Vector{Vector{String}}()
    isfile(path) || return calls
    for line in eachline(path)
        if startswith(line, "CALL ")
            push!(calls, [line[6:end]])
        elseif startswith(line, "ARG ")
            push!(calls[end], line[5:end])
        end
    end
    return calls
end

function record_commands(f; reply = "")
    mktempdir() do dir
        log, reply_file = joinpath(dir, "calls.log"), joinpath(dir, "reply.txt")
        write(reply_file, reply)
        for name in ("ssh", "scp")
            path = joinpath(dir, name)
            write(path, _STUB_SCRIPT)
            chmod(path, 0o755)
        end
        result, output = withenv("PATH" => dir * ":" * ENV["PATH"],
                                 "STUB_LOG" => log, "STUB_REPLY" => reply_file) do
            capture_stdout(f)
        end
        return (calls = _parse_stub_log(log), result = result, output = output)
    end
end

# Run `f()` with SSH_utils.SSH_OPTS set to `opts`, restoring it afterwards so
# no test leaks multiplexing options into another.
function with_ssh_opts(f, opts::Cmd)
    saved = SSH_utils.SSH_OPTS[]
    SSH_utils.SSH_OPTS[] = opts
    try
        return f()
    finally
        SSH_utils.SSH_OPTS[] = saved
    end
end
