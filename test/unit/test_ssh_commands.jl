include(joinpath(@__DIR__, "..", "support", "setup.jl"))

@testset "SSH_commands" begin

    # --- local command vectors ----------------------------------------------

    @testset "ssh_cmd with no options is ssh, user@host, command" begin
        # Arrange
        opts = ``

        # Act
        cmd = SSH_utils.SSH_commands.ssh_cmd(opts, "alice", "cluster", "ls /tmp")

        # Assert
        @test cmd.exec == ["ssh", "alice@cluster", "ls /tmp"]
    end

    @testset "ssh_cmd splices options in before user@host" begin
        # Arrange
        opts = `-o BatchMode=yes`

        # Act
        cmd = SSH_utils.SSH_commands.ssh_cmd(opts, "alice", "cluster", "true")

        # Assert
        @test cmd.exec == ["ssh", "-o", "BatchMode=yes", "alice@cluster", "true"]
    end

    @testset "scp_down_cmd puts -r first and the user@host: prefix on the remote source" begin
        # Arrange
        remote, localdir = "/scratch/out.jld2", "/tmp/data"

        # Act
        cmd = SSH_utils.SSH_commands.scp_down_cmd(``, "alice", "cluster", remote, localdir)

        # Assert
        @test cmd.exec == ["scp", "-r", "alice@cluster:/scratch/out.jld2", "/tmp/data"]
    end

    @testset "scp_up_cmd puts -r first and the user@host: prefix on the remote target" begin
        # Arrange
        remote, localpath = "/scratch/code/", "/tmp/code"

        # Act
        cmd = SSH_utils.SSH_commands.scp_up_cmd(``, "alice", "cluster", remote, localpath)

        # Assert
        @test cmd.exec == ["scp", "-r", "/tmp/code", "alice@cluster:/scratch/code/"]
    end

    @testset "scp_up_file_cmd omits -r" begin
        # Arrange
        remote, localfile = "/scratch/code/", "/tmp/Project.sh"

        # Act
        cmd = SSH_utils.SSH_commands.scp_up_file_cmd(``, "alice", "cluster", remote, localfile)

        # Assert
        @test cmd.exec == ["scp", "/tmp/Project.sh", "alice@cluster:/scratch/code/"]
    end

    @testset "scp commands keep paths with spaces as single arguments" begin
        # Arrange
        remote, localdir = "/scratch/run 1/out", "/tmp/my data"

        # Act
        cmd = SSH_utils.SSH_commands.scp_down_cmd(``, "alice", "cluster", remote, localdir)

        # Assert
        @test cmd.exec == ["scp", "-r", "alice@cluster:/scratch/run 1/out", "/tmp/my data"]
    end

    @testset "controlmaster_opts points ControlPath at %C inside the given directory" begin
        # Arrange
        dir, persist = "/tmp/cm", 600

        # Act
        opts = SSH_utils.SSH_commands.controlmaster_opts(dir, persist)

        # Assert
        @test opts.exec == ["-o", "ControlMaster=auto", "-o", "ControlPath=" * joinpath(dir, "%C"),
                            "-o", "ControlPersist=600"]
    end

    @testset "control_exit_cmd sends -O exit after the options" begin
        # Arrange
        opts = `-o ControlPath=/tmp/cm/%C`

        # Act
        cmd = SSH_utils.SSH_commands.control_exit_cmd(opts, "alice", "cluster")

        # Assert
        @test cmd.exec == ["ssh", "-o", "ControlPath=/tmp/cm/%C", "-O", "exit", "alice@cluster"]
    end

    # --- remote command strings ---------------------------------------------

    @testset "find commands pass literal \\t and \\n through to find" begin
        # Arrange
        root = "/scratch/run/"

        # Act
        mtimes = SSH_utils.SSH_commands.find_mtimes_cmd(root)
        sizes = SSH_utils.SSH_commands.find_sizes_cmd(root)

        # Assert
        @test mtimes == raw"find /scratch/run/ -type f -printf '%T@\t%P\n'"
        @test sizes == raw"find /scratch/run/ -type f -printf '%s\t%P\n'"
        @test !occursin('\t', mtimes) && !occursin('\n', mtimes)
    end

    # --- decisions ----------------------------------------------------------

    @testset "ensure_trailing_slash adds one slash and is idempotent" begin
        # Arrange
        path = "/scratch/run"

        # Act
        once = SSH_utils.SSH_commands.ensure_trailing_slash(path)
        twice = SSH_utils.SSH_commands.ensure_trailing_slash(once)

        # Assert
        @test once == "/scratch/run/"
        @test twice == once
    end

    @testset "parse_find_listing reads value/path pairs in order" begin
        # Arrange
        raw = "1700000000.5\tDF.csv\n1700000001.0\t1/result.txt\n"

        # Act
        entries = SSH_utils.SSH_commands.parse_find_listing(raw, Float64)

        # Assert
        @test entries == [(1700000000.5, "DF.csv"), (1700000001.0, "1/result.txt")]
    end

    @testset "parse_find_listing skips malformed lines and unparseable values" begin
        # Arrange
        raw = "12\tok.txt\nno tab here\nabc\tbad.txt\n1\t2\t3\n\n7\tfine.txt"

        # Act
        entries = SSH_utils.SSH_commands.parse_find_listing(raw, Int)

        # Assert
        @test entries == [(12, "ok.txt"), (7, "fine.txt")]
    end

    @testset "plan_sync downloads a file that is missing locally" begin
        # Arrange
        entries = [(1.0e9, "1/result.txt")]

        # Act
        to_download, n_skipped = mktempdir() do dir
            SSH_utils.SSH_commands.plan_sync(entries, dir)
        end

        # Assert
        @test to_download == ["1/result.txt"]
        @test n_skipped == 0
    end

    @testset "plan_sync downloads a file that is newer on the cluster and skips one that is not" begin
        # Arrange
        dir = mktempdir()
        write(joinpath(dir, "old.txt"), "x")
        write(joinpath(dir, "new.txt"), "x")
        local_mtime = mtime(joinpath(dir, "old.txt"))
        entries = [(local_mtime + 100, "old.txt"), (local_mtime - 100, "new.txt")]

        # Act
        to_download, n_skipped = SSH_utils.SSH_commands.plan_sync(entries, dir)

        # Assert
        @test to_download == ["old.txt"]
        @test n_skipped == 1
    end

    @testset "size_problems reports missing and truncated files and counts every entry" begin
        # Arrange
        dir = mktempdir()
        write(joinpath(dir, "full.bin"), "12345")
        write(joinpath(dir, "short.bin"), "12")
        entries = [(5, "full.bin"), (5, "short.bin"), (5, "gone.bin")]

        # Act
        result = SSH_utils.SSH_commands.size_problems(entries, dir)

        # Assert
        @test result.n == 3
        @test result.bad == [("short.bin", "local 2 B ≠ cluster 5 B"), ("gone.bin", "missing locally")]
    end

    @testset "is_unsafe_remote_path flags empty, root and bare home paths, padded or not" begin
        # Arrange
        unsafe = ["", "/", "~", "~/", "/home", "/home/", "   ", " / ", "\t~/ "]

        # Act
        flags = SSH_utils.SSH_commands.is_unsafe_remote_path.(unsafe)

        # Assert
        @test all(flags)
    end

    @testset "is_unsafe_remote_path accepts a normal scratch path" begin
        # Arrange
        path = "/srv/beegfs/scratch/users/a/alice/run/"

        # Act
        flag = SSH_utils.SSH_commands.is_unsafe_remote_path(path)

        # Assert
        @test !flag
    end

end
