# Slurm job configuration for the Baobab cluster, extracted from
# RunSimulations.pluto.jl. Pure string building, no dependencies: the parsers
# it needs (UI_utils.parse_to_slurm_array / parse_values) are passed in by the
# notebook, so this module loads and tests on its own.
module Slurm_utils

# --- Which simulations -------------------------------------------------------------------

# The notebook's "run everything" switch: any occurrence of "all" or "All".
wants_all(s) = occursin("all", s) || occursin("All", s)

# `--array` spec for every simulation, at most `max_concurrent` running at once.
all_array_spec(nsim; max_concurrent = 40) = "1-$nsim%$max_concurrent"

# `--array` spec for the user's selection; `range_parser` turns "1,3:5" into "1,3-5".
array_spec(s, nsim, range_parser; max_concurrent = 40) =
    wants_all(s) ? all_array_spec(nsim; max_concurrent) : range_parser(s)

# Indices to run locally, one after the other: "" runs the first simulation only.
selected_indices(s, nsim, value_parser) =
    isempty(s) ? [1] : wants_all(s) ? collect(1:nsim) : Int.(value_parser(s))

# --- Where and on what ---------------------------------------------------------------------

# Slurm feature name for each GPU choice offered in the notebook; anything
# else falls back to the 80 GB A100.
gpu_feature(name) = name == "A100-40Gb" ? "nvidia_a100-pcie-40gb" :
                    name == "H100"      ? "nvidia_h100_nvl"       :
                                          "nvidia_a100_80gb_pcie"

gpu_constraint(names) = join(gpu_feature.(names), "|")

partition_spec(private, use_shared_gpu) = use_shared_gpu ? "$private,shared-gpu" : private

# Baobab's per-user layout: /home/users/<initial>/<user>, and the same under scratch.
cluster_home_path(user)    = "/home/users/$(user[1])/$user"
cluster_scratch_path(user) = "/srv/beegfs/scratch/users/$(user[1])/$user"

# --- The job script -----------------------------------------------------------------------

# The sbatch script RunSimulations writes as Project.sh. `data_path` and
# `code_path` are relative to the user's scratch and home, with leading and
# trailing slashes, e.g. "/Data/HydraFluids/". Each array task gets its own
# data folder named after its task id. Built line by line so the trailing
# spaces after --mem and --gpus (kept to reproduce the notebook's original
# script byte for byte) sit inside quotes where no editor strips them; the
# golden test in test/unit/test_slurm_utils.jl pins the whole text.
function batch_script(; array, partition, time, constraint, username,
                        data_path, code_path, mem = 3000, gpus = 1)
    lines = [
        "#!/bin/env bash",
        "#SBATCH --array=$array",
        "#SBATCH --partition=$partition",
        "#SBATCH --time=$time",
        "#SBATCH --output=%J.out",
        "#SBATCH --mem=$mem  ",
        "#SBATCH --gpus=$gpus ",
        "#SBATCH --constraint=$constraint",
        "",
        "export use_gpu=true",
        "export path_to_data=$(cluster_scratch_path(username))$data_path\$SLURM_ARRAY_TASK_ID/",
        "",
        "mkdir -p \$path_to_data",
        "",
        "module load Julia",
        "",
        "cd \$path_to_data",
        "srun julia --optimize=3 $(cluster_home_path(username))$(code_path)main.jl",
    ]
    return join(lines, "\n") * "\n"
end

# Command for running one simulation on this machine. On CPU, `-t auto` gives
# the ParallelStencil Threads backend every core.
local_run_command(; gpu, main_path = "../sim/main.jl") =
    "julia --optimize=3$(gpu ? "" : " -t auto") $main_path"

end
