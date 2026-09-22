include(joinpath(@__DIR__, "..", "support", "setup.jl"))

# The whole offline workflow a user goes through, from the parameter fields
# to downloaded results, with every module wired together as the notebooks
# wire them and a fake cluster in place of Baobab.

if Sys.iswindows()
    @testset "offline workflow" begin
        @test_skip "POSIX stub executables are not available on Windows"
    end
else
@testset "offline workflow" begin

    @testset "a sweep goes from the UI fields to downloaded results" begin
        # Arrange
        fields = (zeta_str = "0:0.5:1", D_str = "10,20")
        user, host = "alice", "cluster"
        data_path, code_path = "/Data/Demo/", "/Code/Demo/"
        localdir = mktempdir()

        # Act
        outcome = with_fake_cluster() do root
            # 1. UI fields -> sweep -> DF.csv
            listtab = [UI_utils.parse_values(fields.zeta_str), UI_utils.parse_values(fields.D_str)]
            df = DF_utils.generate_dataframe(["zeta", "D"], listtab)
            csv = joinpath(localdir, "DF.csv")
            CSV.write(csv, df)

            # 2. read it back
            nsim = size(CSV.read(csv, DataFrame), 1)

            # 3. which simulations
            array = Slurm_utils.array_spec("all", nsim, UI_utils.parse_to_slurm_array)
            chosen = Slurm_utils.selected_indices("1,3:5", nsim, UI_utils.parse_values)

            # 4. the job script
            script = Slurm_utils.batch_script(; array, username = user, data_path, code_path,
                partition = Slurm_utils.partition_spec("private-gpu", true), time = "0-01:00:00",
                constraint = Slurm_utils.gpu_constraint(["H100"]))
            sh = joinpath(localdir, "Project.sh")
            write(sh, script)

            # 5. upload into the (fake) scratch
            remote = root * Slurm_utils.cluster_scratch_path(user) * data_path
            capture_stdout(() -> SSH_utils.mkdir(user, host, remote))
            SSH_utils.up_file(user, host, remote, sh)
            SSH_utils.up_file(user, host, remote, csv)

            # 6. the array tasks write their results on the cluster
            for i in 1:nsim
                SSH_utils.ssh(user, host, "mkdir -p $(remote)$i && echo 'result $i' > $(remote)$i/out.txt")
            end

            # 7. download and verify
            dst = joinpath(localdir, "results")
            n = first(capture_stdout(() -> SSH_utils.sync(user, host, remote, dst)))
            check = SSH_utils.check_download_sizes(user, host, remote, dst)
            (; df, nsim, array, chosen, script, remote, n, check, dst)
        end

        # Assert
        @test collect(zip(outcome.df.zeta, outcome.df.D)) ==
              [(0.0, 10.0), (0.5, 10.0), (1.0, 10.0), (0.0, 20.0), (0.5, 20.0), (1.0, 20.0)]
        @test outcome.nsim == 6
        @test outcome.array == "1-6%40"
        @test outcome.chosen == [1, 3, 4, 5]
        @test occursin("#SBATCH --array=1-6%40\n", outcome.script)
        @test occursin("export path_to_data=/srv/beegfs/scratch/users/a/alice/Data/Demo/\$SLURM_ARRAY_TASK_ID/", outcome.script)
        @test outcome.n == 2 + 6                     # Project.sh, DF.csv and one result per task
        @test outcome.check.n == 8 && isempty(outcome.check.bad)
        @test read(joinpath(outcome.dst, "4", "out.txt"), String) == "result 4\n"
        @test CSV.read(joinpath(outcome.dst, "DF.csv"), DataFrame) == outcome.df
    end

end
end
