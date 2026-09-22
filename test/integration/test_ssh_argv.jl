include(joinpath(@__DIR__, "..", "support", "setup.jl"))

# Characterisation: the exact ssh/scp argument vectors SSH_utils issues, as
# seen by stub executables on PATH. These pin today's behaviour so the
# SSH_utils rewrite can be checked against it; they do not say it is right.

if Sys.iswindows()
    @testset "SSH argument vectors" begin
        @test_skip "POSIX stub executables are not available on Windows"
    end
else
@testset "SSH argument vectors" begin

    @testset "ssh sends the remote command as one argument after user@host" begin
        # Arrange
        cmd = "ls -la /tmp"

        # Act
        rec = record_commands(() -> SSH_utils.ssh("alice", "cluster", cmd); reply = "listing")

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "ls -la /tmp"]]
        @test rec.result == "listing"
    end

    @testset "ssh splices SSH_OPTS in before user@host" begin
        # Arrange
        opts = `-o ControlMaster=auto -o ControlPath=/tmp/cm`

        # Act
        rec = with_ssh_opts(opts) do
            record_commands(() -> SSH_utils.ssh("alice", "cluster", "true"))
        end

        # Assert
        @test rec.calls == [["ssh", "-o", "ControlMaster=auto", "-o", "ControlPath=/tmp/cm", "alice@cluster", "true"]]
    end

    @testset "print_ssh prints what ssh returns" begin
        # Arrange
        cmd = "hostname"

        # Act
        rec = record_commands(() -> SSH_utils.print_ssh("alice", "cluster", cmd); reply = "node01")

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "hostname"]]
        @test rec.output == "node01\n"
    end

    @testset "squeue asks for the caller's own jobs by default" begin
        # Arrange
        usr, hst = "alice", "cluster"

        # Act
        rec = record_commands(() -> SSH_utils.squeue(usr, hst))

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "squeue --me"]]
    end

    @testset "squeue passes a custom option through" begin
        # Arrange
        opt = "-u bob"

        # Act
        rec = record_commands(() -> SSH_utils.squeue("alice", "cluster"; opt = opt))

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "squeue -u bob"]]
    end

    @testset "down copies recursively from user@host:remote to the local path" begin
        # Arrange
        remote, localdir = "/scratch/run 1/out.jld2", "/tmp/my data"

        # Act
        rec = record_commands(() -> SSH_utils.down("alice", "cluster", remote, localdir))

        # Assert
        @test rec.calls == [["scp", "-r", "alice@cluster:/scratch/run 1/out.jld2", "/tmp/my data"]]
    end

    @testset "up copies recursively from the local path to user@host:remote" begin
        # Arrange
        remote, localfile = "/scratch/code/", "/tmp/my code"

        # Act
        rec = record_commands(() -> SSH_utils.up("alice", "cluster", remote, localfile))

        # Assert
        @test rec.calls == [["scp", "-r", "/tmp/my code", "alice@cluster:/scratch/code/"]]
    end

    @testset "up_dir issues exactly the same command as up" begin
        # Arrange
        remote, localdir = "/scratch/code/", "/tmp/my code"

        # Act
        rec_up = record_commands(() -> SSH_utils.up("alice", "cluster", remote, localdir))
        rec_dir = record_commands(() -> SSH_utils.up_dir("alice", "cluster", remote, localdir))

        # Assert
        @test rec_dir.calls == rec_up.calls
    end

    @testset "up_file copies without -r" begin
        # Arrange
        remote, localfile = "/scratch/code/", "/tmp/Project.sh"

        # Act
        rec = record_commands(() -> SSH_utils.up_file("alice", "cluster", remote, localfile))

        # Assert
        @test rec.calls == [["scp", "/tmp/Project.sh", "alice@cluster:/scratch/code/"]]
    end

    @testset "scp commands splice SSH_OPTS in first" begin
        # Arrange
        opts = `-o ControlPath=/tmp/cm`

        # Act
        rec = with_ssh_opts(opts) do
            record_commands(() -> SSH_utils.up_file("alice", "cluster", "/r/", "/l"))
        end

        # Assert
        @test rec.calls == [["scp", "-o", "ControlPath=/tmp/cm", "/l", "alice@cluster:/r/"]]
    end

    @testset "mkdir only checks when the remote directory already exists" begin
        # Arrange
        path = "/scratch/alice/run"

        # Act
        rec = record_commands(() -> SSH_utils.mkdir("alice", "cluster", path); reply = "true")

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "test -d /scratch/alice/run && echo true || echo false"]]
        @test rec.output == "/scratch/alice/run exists\n"
    end

    @testset "mkdir creates the remote directory when it is missing" begin
        # Arrange
        path = "/scratch/alice/run"

        # Act
        rec = record_commands(() -> SSH_utils.mkdir("alice", "cluster", path); reply = "false")

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "test -d /scratch/alice/run && echo true || echo false"],
                            ["ssh", "alice@cluster", "mkdir -p /scratch/alice/run"]]
        @test rec.output == "Create /scratch/alice/run\n"
    end

    @testset "mkdir quotes a path with a space in the remote command" begin
        # Arrange
        path = "/scratch/alice/run 2"

        # Act
        rec = record_commands(() -> SSH_utils.mkdir("alice", "cluster", path); reply = "")

        # Assert
        @test rec.calls[end] == ["ssh", "alice@cluster", "mkdir -p '/scratch/alice/run 2'"]
    end

    @testset "a quoted remote path reaches a POSIX shell as exactly one word" begin
        # Arrange
        paths = ["/scratch/run 2", "/a;exit 7", "/a/it's", "/a/\$HOME", "/a/b*c", "~/my data"]

        # Act
        words = map(paths) do p
            quoted = SSH_utils.SSH_commands.quote_remote_path(p)
            readchomp(`sh -c "set -- $quoted; echo \$#"`)
        end

        # Assert
        @test all(==("1"), words)
    end

    @testset "a quoted ~ path still expands to the remote home directory" begin
        # Arrange
        path = "~/my data"

        # Act
        quoted = SSH_utils.SSH_commands.quote_remote_path(path)
        expanded = withenv("HOME" => "/home/alice") do
            readchomp(`sh -c "printf '%s' $quoted"`)
        end

        # Assert
        @test expanded == "/home/alice/my data"
    end

    @testset "rm_dir refuses each unsafe path without running ssh" begin
        # Arrange
        unsafe = ["", "/", "~", "~/", "/home", "/home/", "  /  ", " ~ "]

        # Act
        outcomes = map(unsafe) do p
            rec = record_commands(() -> try SSH_utils.rm_dir("alice", "cluster", p) catch e; e end)
            (rec.calls, rec.result)
        end

        # Assert
        @test all(isempty(calls) for (calls, _) in outcomes)
        @test all(r isa ErrorException && startswith(r.msg, "rm_dir refused: unsafe path ") for (_, r) in outcomes)
    end

    @testset "rm_dir checks then removes an existing directory" begin
        # Arrange
        path = " /scratch/alice/old "

        # Act
        rec = record_commands(() -> SSH_utils.rm_dir("alice", "cluster", path); reply = "true")

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "test -d /scratch/alice/old && echo true || echo false"],
                            ["ssh", "alice@cluster", "rm -rf /scratch/alice/old"]]
        @test rec.output == "Removed /scratch/alice/old\n"
    end

    @testset "rm_dir stops when the directory does not exist" begin
        # Arrange
        path = "/scratch/alice/old"

        # Act
        rec = record_commands(() -> SSH_utils.rm_dir("alice", "cluster", path); reply = "false")

        # Assert
        @test length(rec.calls) == 1
        @test rec.output == "/scratch/alice/old does not exist\n"
    end

    @testset "readdir lists the remote directory with ls" begin
        # Arrange
        path = "/scratch/alice"

        # Act
        rec = record_commands(() -> SSH_utils.readdir("alice", "cluster", path); reply = "a\nb\n")

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "ls /scratch/alice"]]
        @test rec.result == ["a", "b"]
    end

    @testset "sync lists mtimes with find and downloads each stale file into its folder" begin
        # Arrange
        listing = "1700000000.0\tDF.csv\n1700000000.0\t1/result.txt\n"

        # Act
        rec = mktempdir() do localdir
            r = record_commands(() -> SSH_utils.sync("alice", "cluster", "/scratch/alice/run", localdir); reply = listing)
            (r..., localdir = localdir)
        end

        # Assert
        @test rec.calls[1] == ["ssh", "alice@cluster", "find /scratch/alice/run/ -type f -printf '%T@\\t%P\\n'"]
        @test Set(rec.calls[2:end]) == Set([
            ["scp", "-r", "alice@cluster:/scratch/alice/run/DF.csv", rec.localdir],
            ["scp", "-r", "alice@cluster:/scratch/alice/run/1/result.txt", joinpath(rec.localdir, "1")]])
        @test rec.result == 2
    end

    @testset "check_download_sizes lists byte sizes with find" begin
        # Arrange
        root = "/scratch/alice/run/"

        # Act
        rec = mktempdir() do localdir
            record_commands(() -> SSH_utils.check_download_sizes("alice", "cluster", root, localdir); reply = "")
        end

        # Assert
        @test rec.calls == [["ssh", "alice@cluster", "find /scratch/alice/run/ -type f -printf '%s\\t%P\\n'"]]
    end

    @testset "ssh_close sends -O exit with the multiplexing options, then clears them" begin
        # Arrange
        opts = `-o ControlPath=/tmp/cm`

        # Act
        rec, after = with_ssh_opts(opts) do
            r = record_commands(() -> SSH_utils.ssh_close("alice", "cluster"))
            (r, SSH_utils.SSH_OPTS[])
        end

        # Assert
        @test rec.calls == [["ssh", "-o", "ControlPath=/tmp/cm", "-O", "exit", "alice@cluster"]]
        @test isempty(after.exec)
    end

    @testset "ssh_close does nothing when no multiplexing is active" begin
        # Arrange
        opts = ``

        # Act
        rec = with_ssh_opts(opts) do
            record_commands(() -> SSH_utils.ssh_close("alice", "cluster"))
        end

        # Assert
        @test isempty(rec.calls)
    end

end
end
