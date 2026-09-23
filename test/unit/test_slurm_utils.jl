include(joinpath(@__DIR__, "..", "support", "setup.jl"))

@testset "Slurm_utils" begin

    # --- which simulations --------------------------------------------------

    @testset "wants_all recognises all, All, and all inside a longer string" begin
        # Arrange
        inputs = ["all", "All", "run all of them"]

        # Act
        flags = Slurm_utils.wants_all.(inputs)

        # Assert
        @test all(flags)
    end

    @testset "wants_all is false for an explicit selection" begin
        # Arrange
        input = "1,2"

        # Act
        flag = Slurm_utils.wants_all(input)

        # Assert
        @test !flag
    end

    @testset "all_array_spec runs every simulation, at most 40 at a time" begin
        # Arrange
        nsim = 12

        # Act
        spec = Slurm_utils.all_array_spec(nsim)

        # Assert
        @test spec == "1-12%40"
    end

    @testset "all_array_spec honours max_concurrent" begin
        # Arrange
        nsim = 12

        # Act
        spec = Slurm_utils.all_array_spec(nsim; max_concurrent = 5)

        # Assert
        @test spec == "1-12%5"
    end

    @testset "array_spec uses the all spec when asked for all" begin
        # Arrange
        parser = s -> error("the parser must not be called for \"all\"")

        # Act
        spec = Slurm_utils.array_spec("all", 6, parser)

        # Assert
        @test spec == "1-6%40"
    end

    @testset "array_spec delegates an explicit selection to the injected parser" begin
        # Arrange
        input = "1,3:5"

        # Act
        spec = Slurm_utils.array_spec(input, 6, UI_utils.parse_to_slurm_array)

        # Assert
        @test spec == "1,3-5%40"
    end

    @testset "array_spec throttles an explicit selection like it throttles all" begin
        # Arrange
        input = "1:200"

        # Act
        spec = Slurm_utils.array_spec(input, 200, UI_utils.parse_to_slurm_array; max_concurrent = 10)

        # Assert
        @test spec == "1-200%10"
    end

    @testset "array_spec leaves an empty selection empty rather than emitting a bare %40" begin
        # Arrange
        input = "x"                       # no integers, so the parser drops everything

        # Act
        spec = Slurm_utils.array_spec(input, 6, UI_utils.parse_to_slurm_array)

        # Assert
        @test spec == ""
    end

    @testset "selected_indices runs only the first simulation for an empty selection" begin
        # Arrange
        input = ""

        # Act
        indices = Slurm_utils.selected_indices(input, 6, UI_utils.parse_values)

        # Assert
        @test indices == [1]
    end

    @testset "selected_indices runs every simulation for all" begin
        # Arrange
        input = "all"

        # Act
        indices = Slurm_utils.selected_indices(input, 6, UI_utils.parse_values)

        # Assert
        @test indices == [1, 2, 3, 4, 5, 6]
    end

    @testset "selected_indices expands an explicit selection to integers" begin
        # Arrange
        input = "1,3:5"

        # Act
        indices = Slurm_utils.selected_indices(input, 6, UI_utils.parse_values)

        # Assert
        @test indices == [1, 3, 4, 5]
        @test eltype(indices) == Int
    end

    # --- where and on what --------------------------------------------------

    @testset "gpu_feature maps each notebook GPU choice to its Slurm feature" begin
        # Arrange
        choices = ["H100", "A100-40Gb", "A100-80Gb"]

        # Act
        features = Slurm_utils.gpu_feature.(choices)

        # Assert
        @test features == ["nvidia_h100_nvl", "nvidia_a100-pcie-40gb", "nvidia_a100_80gb_pcie"]
    end

    @testset "gpu_feature falls back to the 80 GB A100 for anything else" begin
        # Arrange
        choice = "V100"

        # Act
        feature = Slurm_utils.gpu_feature(choice)

        # Assert
        @test feature == "nvidia_a100_80gb_pcie"
    end

    @testset "gpu_constraint joins several features with |" begin
        # Arrange
        choices = ["A100-40Gb", "H100"]

        # Act
        constraint = Slurm_utils.gpu_constraint(choices)

        # Assert
        @test constraint == "nvidia_a100-pcie-40gb|nvidia_h100_nvl"
    end

    @testset "gpu_constraint of a single GPU has no separator" begin
        # Arrange
        choices = ["H100"]

        # Act
        constraint = Slurm_utils.gpu_constraint(choices)

        # Assert
        @test constraint == "nvidia_h100_nvl"
    end

    @testset "gpu_constraint of no GPUs is empty" begin
        # Arrange
        choices = String[]

        # Act
        constraint = Slurm_utils.gpu_constraint(choices)

        # Assert
        @test constraint == ""
    end

    @testset "partition_spec adds shared-gpu when requested" begin
        # Arrange
        private = "private-kruse-gpu"

        # Act
        with_shared = Slurm_utils.partition_spec(private, true)
        without = Slurm_utils.partition_spec(private, false)

        # Assert
        @test with_shared == "private-kruse-gpu,shared-gpu"
        @test without == "private-kruse-gpu"
    end

    @testset "cluster paths are filed under the username's first letter" begin
        # Arrange
        user = "dumoulil"

        # Act
        home = Slurm_utils.cluster_home_path(user)
        scratch = Slurm_utils.cluster_scratch_path(user)

        # Assert
        @test home == "/home/users/d/dumoulil"
        @test scratch == "/srv/beegfs/scratch/users/d/dumoulil"
    end

    # --- the job script -----------------------------------------------------

    @testset "batch_script reproduces the notebook's script exactly" begin
        # Arrange
        spec = (array = Slurm_utils.array_spec("all", 6, UI_utils.parse_to_slurm_array),
                partition = Slurm_utils.partition_spec("private-kruse-gpu", true),
                time = "0-12:00:00",
                constraint = Slurm_utils.gpu_constraint(["A100-40Gb", "H100"]),
                username = "dumoulil",
                data_path = "/Data/HydraFluids/",
                code_path = "/Code/HydraFluids/")

        # Act
        script = Slurm_utils.batch_script(; spec...)

        # Assert
        @test script == golden_batch_script()
    end

    @testset "batch_script keeps the invariant header and exports use_gpu before mkdir" begin
        # Arrange
        spec = (array = "1-3", partition = "p", time = "1:00:00", constraint = "c",
                username = "alice", data_path = "/D/", code_path = "/C/")

        # Act
        lines = split(Slurm_utils.batch_script(; spec...), "\n")

        # Assert
        @test "#SBATCH --output=%J.out" in lines
        @test "#SBATCH --mem=3000  " in lines
        @test "#SBATCH --gpus=1 " in lines
        @test findfirst(==("export use_gpu=true"), lines) < findfirst(==("mkdir -p \$path_to_data"), lines)
    end

    @testset "batch_script passes mem and gpus through when given" begin
        # Arrange
        spec = (array = "1", partition = "p", time = "1:00:00", constraint = "c",
                username = "alice", data_path = "/D/", code_path = "/C/", mem = 8000, gpus = 2)

        # Act
        script = Slurm_utils.batch_script(; spec...)

        # Assert
        @test occursin("#SBATCH --mem=8000", script)
        @test occursin("#SBATCH --gpus=2", script)
    end

    @testset "local_run_command gives the CPU run every thread" begin
        # Arrange
        gpu = false

        # Act
        cmd = Slurm_utils.local_run_command(; gpu)

        # Assert
        @test cmd == "julia --optimize=3 -t auto ../sim/main.jl"
    end

    @testset "local_run_command leaves threads alone on the GPU" begin
        # Arrange
        gpu = true

        # Act
        cmd = Slurm_utils.local_run_command(; gpu)

        # Assert
        @test cmd == "julia --optimize=3 ../sim/main.jl"
    end

end
