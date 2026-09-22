module SSH_utils

# Both are included relative to this file, so this also works when a notebook
# includes SSH_utils. Tests reach them as SSH_utils.Runner / SSH_utils.SSH_commands.
include("Runner.jl")         # process-execution seam: capture / execute
include("SSH_commands.jl")   # pure: command construction and sync planning
using .Runner
using .SSH_commands: ssh_cmd, scp_down_cmd, scp_up_cmd, scp_up_file_cmd, controlmaster_opts,
                     control_exit_cmd, find_mtimes_cmd, find_sizes_cmd, mkdir_cmd,
                     isdir_cmd, rm_rf_cmd, ls_cmd, ensure_trailing_slash, parse_find_listing,
                     plan_sync, size_problems, is_unsafe_remote_path

# `mkdir` and `readdir` are deliberately not exported: they would clash with
# Base under `using`. Call them qualified, as SSH_utils.mkdir(...).
export ssh, print_ssh, squeue, down, up, up_dir, up_file, sync, check_download_sizes,
       rm_dir, isloaded, ssh_open, ssh_close

# Every function builds its command with SSH_commands and hands it to a runner.
# The keywords `opts` (ssh/scp options, default: the SSH_OPTS set by ssh_open)
# and `runner` (default: really run it) exist so tests can be hermetic; the
# notebooks never pass them.

# --- Optional SSH connection multiplexing (opt-in, fully additive) -----------------------
# `SSH_OPTS` is EMPTY by default, so every function below behaves EXACTLY as before — one
# login per ssh/scp — on every platform, including Windows. Nothing here changes unless you
# opt in by calling `ssh_open(usr, hst)`.
#
# After `ssh_open` (on macOS/Linux) `SSH_OPTS` holds OpenSSH ControlMaster options, so all
# subsequent ssh/scp — including the parallel downloads in `sync` — REUSE one shared master
# connection: a whole submit/sync session becomes a single login and no longer trips the
# cluster's "too many logins" rate-limit. The master is kept alive for `CONTROL_PERSIST`
# seconds after the last use. `ssh_close` tears it down and reverts to the default behaviour.
#
# Windows' bundled OpenSSH has no ControlMaster, so there `ssh_open` only checks connectivity
# and leaves `SSH_OPTS` empty — calls stay one-login-each and keep working. Complement with an
# ssh-agent (`ssh-add` your key once) so a passphrase-protected key is unlocked a single time.
const SSH_OPTS = Ref{Cmd}(``)
const CM_DIR = joinpath(homedir(), ".ssh", "controlmasters")
const CONTROL_PERSIST = 600   # seconds the master stays alive after the last connection

ssh(usr, hst, cmd; opts = SSH_OPTS[], runner = ShellRunner()) =
    capture(runner, ssh_cmd(opts, usr, hst, cmd))

print_ssh(usr, hst, cmd; kw...) = println(ssh(usr, hst, cmd; kw...))

# Open (or refresh) the shared master connection so the following ssh/scp all reuse one
# login; returns the remote `user@host` as a connectivity check. On Windows it just verifies
# connectivity (multiplexing unsupported) and leaves the one-login-per-call behaviour intact.
# `dir` is where the control sockets live (tests point it at a temp directory).
function ssh_open(usr, hst; runner = ShellRunner(), dir = CM_DIR)
    if !Sys.iswindows()
        isdir(dir) || mkpath(dir)
        SSH_OPTS[] = controlmaster_opts(dir, CONTROL_PERSIST)
    end
    ssh(usr, hst, "echo \$(whoami)@\$(hostname)"; runner)   # authenticates once and opens the master
end

# Close the shared master connection (if any) and revert to one-login-per-call behaviour.
# Best effort: a master that has already gone away is not an error.
function ssh_close(usr, hst; runner = ShellRunner())
    if !Sys.iswindows() && !isempty(SSH_OPTS[].exec)
        try; execute(runner, control_exit_cmd(SSH_OPTS[], usr, hst)); catch; end
    end
    SSH_OPTS[] = ``
    nothing
end

# Query the Slurm scheduler over SSH and RETURN the output as a String (unlike print_ssh,
# which only prints), so it can be displayed/refreshed in a notebook cell. Default
# `opt="--me"` lists the caller's own jobs.
squeue(usr, hst; opt = "--me", kw...) = ssh(usr, hst, "squeue $opt"; kw...)

down(usr, hst, cluster_file_path, local_directory_path; opts = SSH_OPTS[], runner = ShellRunner()) =
    execute(runner, scp_down_cmd(opts, usr, hst, cluster_file_path, local_directory_path))

up(usr, hst, cluster_directory_path, local_file_path; opts = SSH_OPTS[], runner = ShellRunner()) =
    execute(runner, scp_up_cmd(opts, usr, hst, cluster_directory_path, local_file_path))

# Same command as `up` (kept for API compatibility): a recursive copy handles a
# directory and a file alike.
up_dir(usr, hst, cluster_directory_path, local_directory_path; kw...) =
    up(usr, hst, cluster_directory_path, local_directory_path; kw...)

up_file(usr, hst, cluster_directory_path, local_file_path; opts = SSH_OPTS[], runner = ShellRunner()) =
    execute(runner, scp_up_file_cmd(opts, usr, hst, cluster_directory_path, local_file_path))

# Download a remote directory tree, transferring only files that are missing
# locally or newer on the cluster. Cross-platform (Windows/macOS/Linux): it uses
# only `ssh`/`scp` and compares modification times in Julia, so no `rsync` is
# required. Returns the number of files downloaded.
function sync(usr, hst, cluster_directory_path, local_directory_path;
              nparallel = 4, opts = SSH_OPTS[], runner = ShellRunner())
    root = ensure_trailing_slash(cluster_directory_path)
    listing = ssh(usr, hst, find_mtimes_cmd(root); opts, runner)
    to_download, n_skipped = plan_sync(parse_find_listing(listing, Float64), local_directory_path)
    println("$(length(to_download)) file(s) to download, $n_skipped already up-to-date")
    # Create the destination sub-folders up front so the parallel tasks below
    # don't race on mkpath.
    for rel in to_download
        mkpath(dirname(joinpath(local_directory_path, rel)))
    end
    # Download up to `nparallel` files at a time. Each `scp` is its own process
    # and `run` yields while waiting, so the transfers overlap. The semaphore
    # keeps us under the cluster's concurrent-SSH limit.
    sem = Base.Semaphore(max(nparallel, 1))
    @sync for rel in to_download
        @async Base.acquire(sem) do
            down(usr, hst, root * rel, dirname(joinpath(local_directory_path, rel)); opts, runner)
            println("   downloaded  ", rel)
        end
    end
    println("Done: $(length(to_download)) file(s) downloaded into $local_directory_path")
    return length(to_download)
end

# Compare each remote file's byte size to its local copy — catches truncated / incomplete
# downloads (a dropped connection) and files missing locally. Returns `(n, bad)`, where `bad`
# is a vector of `(relative_path, reason)`. One remote `find`; reads nothing locally beyond
# `filesize`, so it stays fast even for large trees.
function check_download_sizes(usr, hst, remote_directory_path, local_directory_path; kw...)
    root = ensure_trailing_slash(remote_directory_path)
    listing = ssh(usr, hst, find_sizes_cmd(root); kw...)
    return size_problems(parse_find_listing(listing, Int), local_directory_path)
end

function mkdir(u, h, cluster_directory_path; kw...)
    if ssh(u, h, isdir_cmd(cluster_directory_path); kw...) == "true"
        println("$cluster_directory_path exists")
    else
        ssh(u, h, mkdir_cmd(cluster_directory_path); kw...)
        println("Create $cluster_directory_path")
    end
end

# Remove a remote directory (recursively, `rm -rf`). A few sanity checks guard
# against wiping the wrong thing: the path must be non-empty and not the
# filesystem root or the user's bare home directory.
function rm_dir(u, h, cluster_directory_path; kw...)
    is_unsafe_remote_path(cluster_directory_path) &&
        error("rm_dir refused: unsafe path $(repr(cluster_directory_path))")
    path = strip(cluster_directory_path)
    if ssh(u, h, isdir_cmd(path); kw...) != "true"
        println("$path does not exist")
        return nothing
    end
    ssh(u, h, rm_rf_cmd(path); kw...)
    println("Removed $path")
end

readdir(u, h, cluster_directory_path; kw...) =
    split(ssh(u, h, ls_cmd(cluster_directory_path); kw...), "\n", keepempty=false)

isloaded() = true

end
