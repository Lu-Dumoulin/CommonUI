# =============================================================================
# A fake cluster for integration tests. No tests here.
#
# `with_fake_cluster(f; files)` creates a temp directory standing in for the
# cluster filesystem, writes `files` (relative path => content) into it, puts
# stub `ssh`, `scp` and `squeue` executables first on PATH, and calls
# `f(root)`. Remote absolute paths are real local paths, so tests build
# remote paths under `root`.
#
#   ssh     skips its options and user@host, then runs the remote command
#           with `sh -c` locally; `-O exit` (ControlMaster teardown) is a no-op.
#           GNU `find -printf '%T@\t%P\n'` / `'%s\t%P\n'` are emulated, since
#           macOS find has no -printf.
#   scp     skips its options, strips the user@host: prefix, and copies with cp -R.
#   squeue  prints "squeue <args>", so tests can see what was asked.
#
# POSIX only: callers skip on Windows.
# =============================================================================

const _FAKE_PRELUDE = raw"""
# Sourced before every remote command the ssh stub runs.
if stat -f %Fm / >/dev/null 2>&1; then
    _mtime() { stat -f %Fm "$1"; }; _size() { stat -f %z "$1"; }        # BSD / macOS
else
    _mtime() { stat -c %.9Y "$1"; }; _size() { stat -c %s "$1"; }       # GNU
fi
find() {
    if [ "$#" -eq 5 ] && [ "$2" = "-type" ] && [ "$3" = "f" ] && [ "$4" = "-printf" ]; then
        _root=$1; _fmt=$5
        command find "$_root" -type f | while IFS= read -r _f; do
            _rel=${_f#"$_root"}; _rel=${_rel#/}
            case "$_fmt" in
                '%T@\t%P\n') printf '%s\t%s\n' "$(_mtime "$_f")" "$_rel" ;;
                '%s\t%P\n')  printf '%s\t%s\n' "$(_size "$_f")" "$_rel" ;;
                *) echo "fake find: unsupported -printf $_fmt" >&2; exit 2 ;;
            esac
        done
    else
        command find "$@"
    fi
}
"""

const _FAKE_SSH = raw"""
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) exit 0 ;;
        -o) shift 2 ;;
        -*) shift ;;
        *)  break ;;
    esac
done
shift                                   # user@host
exec sh -c ". \"$FAKE_PRELUDE\"; $*"
"""

const _FAKE_SCP = raw"""
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift 2 ;;
        -*) shift ;;
        *)  break ;;
    esac
done
src=${1#*@*:}; dst=${2#*@*:}
exec cp -R "$src" "$dst"
"""

const _FAKE_SQUEUE = raw"""
#!/bin/sh
echo "squeue $*"
"""

function with_fake_cluster(f; files = Dict{String,String}())
    mktempdir() do dir
        bin, root = joinpath(dir, "bin"), joinpath(dir, "cluster")
        mkpath(bin); mkpath(root)
        for (rel, content) in files
            put_file(root, rel, content)
        end
        prelude = joinpath(bin, "prelude.sh")
        write(prelude, _FAKE_PRELUDE)
        for (name, script) in ("ssh" => _FAKE_SSH, "scp" => _FAKE_SCP, "squeue" => _FAKE_SQUEUE)
            path = joinpath(bin, name)
            write(path, script)
            chmod(path, 0o755)
        end
        withenv("PATH" => bin * ":" * ENV["PATH"], "FAKE_PRELUDE" => prelude) do
            with_ssh_opts(``) do
                f(root)
            end
        end
    end
end

# Write `content` to `root/rel`, creating parent directories.
function put_file(root, rel, content)
    path = joinpath(root, rel)
    mkpath(dirname(path))
    write(path, content)
    return path
end
