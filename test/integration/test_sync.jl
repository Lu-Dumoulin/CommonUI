include(joinpath(@__DIR__, "..", "support", "setup.jl"))

# sync and check_download_sizes against a fake cluster.

if Sys.iswindows()
    @testset "sync on a fake cluster" begin
        @test_skip "POSIX stub executables are not available on Windows"
    end
else
@testset "sync on a fake cluster" begin

    @testset "a fresh sync downloads every file and rebuilds the folder structure" begin
        # Arrange
        dst = joinpath(mktempdir(), "dst")          # does not exist yet
        files = Dict("run/DF.csv" => "a,b\n1,2\n", "run/1/result.txt" => "sim 1\n", "run/2/result.txt" => "sim 2\n")

        # Act
        n = with_fake_cluster(; files) do root
            first(capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst)))
        end

        # Assert
        @test n == 3
        @test read(joinpath(dst, "1", "result.txt"), String) == "sim 1\n"
        @test read(joinpath(dst, "2", "result.txt"), String) == "sim 2\n"
        @test isfile(joinpath(dst, "DF.csv"))
    end

    @testset "an immediate second sync downloads nothing" begin
        # Arrange
        dst = mktempdir()
        files = Dict("run/1/result.txt" => "sim 1\n", "run/2/result.txt" => "sim 2\n")

        # Act
        n_second = with_fake_cluster(; files) do root
            capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst))
            first(capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst)))
        end

        # Assert
        @test n_second == 0
    end

    @testset "rewriting one remote file re-downloads exactly that file" begin
        # Arrange
        dst = mktempdir()
        files = Dict("run/1/result.txt" => "old\n", "run/2/result.txt" => "sim 2\n")

        # Act
        n_after, content = with_fake_cluster(; files) do root
            capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst))
            sleep(0.05)                               # the rewrite must be strictly newer
            put_file(root, "run/1/result.txt", "new\n")
            n = first(capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst)))
            (n, read(joinpath(dst, "1", "result.txt"), String))
        end

        # Assert
        @test n_after == 1
        @test content == "new\n"
    end

    @testset "nparallel = 1 and nparallel = 4 download the same tree" begin
        # Arrange
        dst1, dst4 = mktempdir(), mktempdir()
        files = Dict("run/$i/result.txt" => "sim $i\n" for i in 1:12)

        # Act
        with_fake_cluster(; files) do root
            capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst1; nparallel = 1))
            capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "run"), dst4; nparallel = 4))
        end

        # Assert
        tree(d) = sort([(relpath(joinpath(p, f), d), read(joinpath(p, f), String)) for (p, _, fs) in walkdir(d) for f in fs])
        @test length(tree(dst1)) == 12
        @test tree(dst1) == tree(dst4)
    end

    @testset "sync handles a remote folder whose path has a space" begin
        # Arrange
        dst = mktempdir()
        files = Dict("my run/1/result.txt" => "sim 1\n")

        # Act
        n = with_fake_cluster(; files) do root
            first(capture_stdout(() -> SSH_utils.sync("alice", "cluster", joinpath(root, "my run"), dst)))
        end

        # Assert
        @test n == 1
        @test isfile(joinpath(dst, "1", "result.txt"))
    end

    @testset "check_download_sizes reports a truncated local file and a missing one" begin
        # Arrange
        dst = mktempdir()
        put_file(dst, "full.bin", "12345")
        put_file(dst, "short.bin", "12")
        files = Dict("run/full.bin" => "12345", "run/short.bin" => "12345", "run/gone.bin" => "12345")

        # Act
        result = with_fake_cluster(; files) do root
            SSH_utils.check_download_sizes("alice", "cluster", joinpath(root, "run"), dst)
        end

        # Assert
        @test result.n == 3
        @test Set(result.bad) == Set([("short.bin", "local 2 B ≠ cluster 5 B"), ("gone.bin", "missing locally")])
    end

end
end
