include(joinpath(@__DIR__, "..", "support", "setup.jl"))

# SSH_utils against a fake cluster: real ssh/scp subprocesses (stubs on PATH)
# acting on a temp directory, so argument quoting, exit codes and file
# transfer all run for real, with no network.

if Sys.iswindows()
    @testset "SSH_utils on a fake cluster" begin
        @test_skip "POSIX stub executables are not available on Windows"
    end
else
@testset "SSH_utils on a fake cluster" begin

    @testset "ssh returns the remote command's stdout" begin
        # Arrange
        cmd = "echo hello from the cluster"

        # Act
        result = with_fake_cluster(root -> SSH_utils.ssh("alice", "cluster", cmd))

        # Assert
        @test result == "hello from the cluster"
    end

    @testset "ssh raises when the remote command fails" begin
        # Arrange
        cmd = "exit 3"

        # Act
        call = () -> with_fake_cluster(root -> SSH_utils.ssh("alice", "cluster", cmd))

        # Assert
        @test_throws ProcessFailedException call()
    end

    @testset "squeue asks the scheduler for the caller's own jobs by default" begin
        # Arrange
        usr, hst = "alice", "cluster"

        # Act
        result = with_fake_cluster(root -> SSH_utils.squeue(usr, hst))

        # Assert
        @test result == "squeue --me"
    end

    @testset "mkdir creates the remote directory, then reports it exists" begin
        # Arrange
        name = "run"

        # Act
        created, first, second = with_fake_cluster() do root
            path = joinpath(root, name)
            _, out1 = capture_stdout(() -> SSH_utils.mkdir("alice", "cluster", path))
            _, out2 = capture_stdout(() -> SSH_utils.mkdir("alice", "cluster", path))
            (isdir(path), out1, out2)
        end

        # Assert
        @test created
        @test startswith(first, "Create ")
        @test endswith(second, "run exists\n")
    end

    @testset "mkdir creates exactly one directory for a path with a space" begin
        # Arrange
        name = "run 2"

        # Act
        entries = with_fake_cluster() do root
            capture_stdout(() -> SSH_utils.mkdir("alice", "cluster", joinpath(root, name)))
            readdir(root)
        end

        # Assert
        @test entries == ["run 2"]
    end

    @testset "up_file puts a local file into the remote directory" begin
        # Arrange
        script = put_file(mktempdir(), "Project.sh", "#!/bin/bash\n")
        files = Dict("code/.keep" => "")

        # Act
        content = with_fake_cluster(; files) do root
            SSH_utils.up_file("alice", "cluster", joinpath(root, "code") * "/", script)
            read(joinpath(root, "code", "Project.sh"), String)
        end

        # Assert
        @test content == "#!/bin/bash\n"
    end

    @testset "up_dir copies a local directory tree into the remote directory" begin
        # Arrange
        localdir = mktempdir()
        put_file(localdir, "sim/main.jl", "main()")
        put_file(localdir, "sim/kernels/k.jl", "k")

        # Act
        files = with_fake_cluster() do root
            SSH_utils.up_dir("alice", "cluster", root * "/", joinpath(localdir, "sim"))
            sort([relpath(joinpath(d, f), root) for (d, _, fs) in walkdir(root) for f in fs])
        end

        # Assert
        @test files == [joinpath("sim", "kernels", "k.jl"), joinpath("sim", "main.jl")]
    end

    @testset "down retrieves a remote file into a local directory" begin
        # Arrange
        localdir = mktempdir()
        files = Dict("run/out.csv" => "t,E\n0,1\n")

        # Act
        with_fake_cluster(; files) do root
            SSH_utils.down("alice", "cluster", joinpath(root, "run", "out.csv"), localdir)
        end

        # Assert
        @test read(joinpath(localdir, "out.csv"), String) == "t,E\n0,1\n"
    end

    @testset "readdir lists the remote directory" begin
        # Arrange
        files = Dict("run/1/a" => "", "run/2/b" => "", "run/DF.csv" => "")

        # Act
        listing = with_fake_cluster(; files) do root
            SSH_utils.readdir("alice", "cluster", joinpath(root, "run"))
        end

        # Assert
        @test listing == ["1", "2", "DF.csv"]
    end

    @testset "rm_dir removes the directory and leaves its siblings" begin
        # Arrange
        files = Dict("old/x" => "", "keep/y" => "")

        # Act
        remaining, output = with_fake_cluster(; files) do root
            _, out = capture_stdout(() -> SSH_utils.rm_dir("alice", "cluster", joinpath(root, "old")))
            (readdir(root), out)
        end

        # Assert
        @test remaining == ["keep"]
        @test startswith(output, "Removed ")
    end

    @testset "rm_dir removes only the named directory when its path has a space" begin
        # Arrange
        files = Dict("run 2/x" => "", "run/y" => "", "2/z" => "")

        # Act
        remaining = with_fake_cluster(; files) do root
            capture_stdout(() -> SSH_utils.rm_dir("alice", "cluster", joinpath(root, "run 2")))
            readdir(root)
        end

        # Assert
        @test remaining == ["2", "run"]
    end

    @testset "rm_dir reports a directory that does not exist" begin
        # Arrange
        name = "nope"

        # Act
        output = with_fake_cluster() do root
            last(capture_stdout(() -> SSH_utils.rm_dir("alice", "cluster", joinpath(root, name))))
        end

        # Assert
        @test endswith(output, "nope does not exist\n")
    end

    @testset "ssh_open turns multiplexing on for later commands and ssh_close turns it off" begin
        # Arrange
        cmdir = mktempdir()
        runner = FakeRunner()

        # Act
        after = with_fake_cluster() do root
            SSH_utils.ssh_open("alice", "cluster"; dir = cmdir)
            SSH_utils.ssh("alice", "cluster", "true"; runner)
            SSH_utils.ssh_close("alice", "cluster")
            SSH_utils.SSH_OPTS[]
        end

        # Assert
        during = recorded(runner)[1]
        @test "ControlMaster=auto" in during
        @test "ControlPath=" * joinpath(cmdir, "%C") in during
        @test isempty(after.exec)
    end

end
end
