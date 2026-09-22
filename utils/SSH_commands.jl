# Pure half of SSH_utils: builds every ssh/scp command and decides what to do
# with the answers. Nothing here spawns a process; the only I/O is read-only
# local filesystem queries (`isfile`, `mtime`, `filesize`) in the planning
# functions. SSH_utils hands the commands to a runner.
module SSH_commands

# --- Local commands (ssh / scp argument vectors) --------------------------------------
# Interpolated values in a Cmd are never word-split, so paths with spaces stay
# one argument each on this side. The remote side of scp is left unquoted on
# purpose: since OpenSSH 9, scp uses the SFTP protocol by default and no shell
# parses the path, so quoting would add literal quote characters.

remote_target(usr, hst) = "$usr@$hst"

ssh_cmd(opts::Cmd, usr, hst, remote_cmd) = `ssh $opts $(remote_target(usr, hst)) $remote_cmd`

scp_down_cmd(opts::Cmd, usr, hst, remote_path, local_path) =
    `scp $opts -r $(remote_target(usr, hst)):$remote_path $local_path`

scp_up_cmd(opts::Cmd, usr, hst, remote_path, local_path) =
    `scp $opts -r $local_path $(remote_target(usr, hst)):$remote_path`

scp_up_file_cmd(opts::Cmd, usr, hst, remote_path, local_path) =
    `scp $opts $local_path $(remote_target(usr, hst)):$remote_path`

# OpenSSH connection multiplexing. %C is a short fixed-length hash of (localhost,
# remotehost, port, user); it keeps the control-socket path under the ~104-char
# Unix-socket limit.
controlmaster_opts(dir, persist) =
    `-o ControlMaster=auto -o ControlPath=$(joinpath(dir, "%C")) -o ControlPersist=$persist`

control_exit_cmd(opts::Cmd, usr, hst) = `ssh $opts -O exit $(remote_target(usr, hst))`

# --- Remote commands (strings run by the remote shell) --------------------------------
# The remote shell word-splits these strings again, so every path is quoted
# with `quote_remote_path`. Ordinary absolute paths come back unchanged.
# `find -printf` runs on the cluster (GNU find), so it is unaffected by the client OS.
# The \\t and \\n stay double-backslashed: find interprets them, not Julia.

# One POSIX shell word for `path`. A leading `~` or `~/` stays outside the
# quotes so the remote shell still expands it to the home directory.
function quote_remote_path(path::AbstractString)
    path == "~" && return "~"
    startswith(path, "~/") && return "~/" * Base.shell_escape_posixly(path[3:end])
    return Base.shell_escape_posixly(path)
end

find_mtimes_cmd(root) = "find $(quote_remote_path(root)) -type f -printf '%T@\\t%P\\n'"
find_sizes_cmd(root)  = "find $(quote_remote_path(root)) -type f -printf '%s\\t%P\\n'"

# Prints "true" when the directory exists, "false" otherwise.
isdir_cmd(path)       = "test -d $(quote_remote_path(path)) && echo true || echo false"
mkdir_cmd(path)       = "mkdir -p $(quote_remote_path(path))"
rm_rf_cmd(path)       = "rm -rf $(quote_remote_path(path))"
ls_cmd(path)          = "ls $(quote_remote_path(path))"

# --- Decisions -------------------------------------------------------------------------

ensure_trailing_slash(path) = endswith(path, "/") ? path : path * "/"

# Parse `find -printf '<value>\t<relative path>\n'` output into (value, path)
# pairs, skipping malformed lines and values that do not parse as T.
function parse_find_listing(raw::AbstractString, ::Type{T}) where {T}
    entries = Tuple{T,String}[]
    for line in split(raw, "\n", keepempty=false)
        parts = split(line, "\t")
        length(parts) == 2 || continue
        value = tryparse(T, parts[1])
        isnothing(value) && continue
        push!(entries, (value, String(parts[2])))
    end
    return entries
end

# Which remote files need downloading: those missing locally or newer on the
# cluster. `entries` are (remote mtime, relative path) pairs. Returns the
# relative paths to download, in listing order, and how many were up to date.
function plan_sync(entries, local_dir)
    to_download = String[]
    n_skipped = 0
    for (remote_mtime, rel) in entries
        local_path = joinpath(local_dir, rel)
        if !isfile(local_path) || remote_mtime > mtime(local_path)
            push!(to_download, rel)
        else
            n_skipped += 1
        end
    end
    return to_download, n_skipped
end

# Compare remote byte sizes to the local copies. `entries` are (remote size,
# relative path) pairs. Returns `(n, bad)`, where `bad` holds
# (relative path, reason) for each file that is missing or differs.
function size_problems(entries, local_dir)
    bad = Tuple{String,String}[]
    for (rsize, rel) in entries
        lpath = joinpath(local_dir, rel)
        if !isfile(lpath)
            push!(bad, (rel, "missing locally"))
        elseif filesize(lpath) != rsize
            push!(bad, (rel, "local $(filesize(lpath)) B ≠ cluster $rsize B"))
        end
    end
    return (n = length(entries), bad = bad)
end

# The rm_dir guard: paths that must never be removed recursively, ignoring
# surrounding whitespace.
function is_unsafe_remote_path(path)
    p = strip(path)
    return isempty(p) || p in ("/", "~", "~/", "/home", "/home/")
end

end
