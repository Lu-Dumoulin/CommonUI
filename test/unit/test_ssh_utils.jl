include(joinpath(@__DIR__, "..", "support", "setup.jl"))

# SSH_utils driven through a FakeRunner: which commands are issued, and when
# none are. The real-process view of the same functions is in
# integration/test_ssh_argv.jl.

@testset "SSH_utils with a FakeRunner" begin

    @testset "ssh hands its command to the runner and returns the reply" begin
        # Arrange
        runner = FakeRunner("node01")

        # Act
        result = SSH_utils.ssh("alice", "cluster", "hostname"; runner)

        # Assert
        @test result == "node01"
        @test recorded(runner) == [["ssh", "alice@cluster", "hostname"]]
    end

    @testset "an explicit opts keyword overrides the global SSH_OPTS" begin
        # Arrange
        runner = FakeRunner()

        # Act
        with_ssh_opts(`-o Global=yes`) do
            SSH_utils.ssh("alice", "cluster", "true"; opts = ``, runner)
        end

        # Assert
        @test recorded(runner) == [["ssh", "alice@cluster", "true"]]
    end

    @testset "rm_dir refuses an unsafe path without issuing any command" begin
        # Arrange
        runner = FakeRunner("true")

        # Act
        call = () -> SSH_utils.rm_dir("alice", "cluster", " ~/ "; runner)

        # Assert
        @test_throws "rm_dir refused: unsafe path \" ~/ \"" call()
        @test isempty(runner.calls)
    end

    @testset "sync downloads only the stale files, each into its own folder" begin
        # Arrange
        dir = mktempdir()
        write(joinpath(dir, "fresh.txt"), "x")
        now_ = mtime(joinpath(dir, "fresh.txt"))
        listing = "$(now_ - 100)\tfresh.txt\n$(now_ + 100)\tsub/new.txt\n"
        runner = FakeRunner(cmd -> occursin("find", cmd.exec[end]) ? listing : "")

        # Act
        n, output = capture_stdout(() -> SSH_utils.sync("alice", "cluster", "/r", dir; opts = ``, runner))

        # Assert
        @test n == 1
        @test recorded(runner)[2:end] == [["scp", "-r", "alice@cluster:/r/sub/new.txt", joinpath(dir, "sub")]]
        @test isdir(joinpath(dir, "sub"))
        @test startswith(output, "1 file(s) to download, 1 already up-to-date\n")
    end

    @testset "check_download_sizes returns the count and the problems" begin
        # Arrange
        dir = mktempdir()
        write(joinpath(dir, "a.bin"), "123")
        runner = FakeRunner("3\ta.bin\n9\tb.bin\n")

        # Act
        result = SSH_utils.check_download_sizes("alice", "cluster", "/r", dir; opts = ``, runner)

        # Assert
        @test result.n == 2
        @test result.bad == [("b.bin", "missing locally")]
    end

end
