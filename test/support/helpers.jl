# =============================================================================
# Shared test helpers and fixtures. No tests here.
# =============================================================================

"""
    capture_stdout(f) -> (result, output::String)

Call `f()` with stdout redirected to a temporary file and return its result
together with everything it printed.
"""
function capture_stdout(f)
    mktemp() do path, io
        result = redirect_stdout(f, io)
        flush(io)
        return result, read(path, String)
    end
end

"""
    two_parameter_sweep() -> (listname, listtab)

The reference sweep: two values of `alpha` crossed with three values of
`beta`, six simulations in total, whose row order the DF_utils tests pin.
"""
two_parameter_sweep() = (["alpha", "beta"], [[0.1, 0.2], [10, 20, 30]])

"""
    golden_batch_script() -> String

The sbatch script RunSimulations.pluto.jl generated before Slurm_utils
existed, for `"all"` of 6 simulations, user `dumoulil`, partitions
`private-kruse-gpu` + shared, the notebook's default GPUs, 12 h, and the
HydraFluids data and code paths. Captured by evaluating the notebook
cell's own code, minus the two stray tabs its indented closing \"\"\"
left after the last line. Written with explicit escapes so no editor can
strip the trailing spaces on the --mem and --gpus lines.
"""
golden_batch_script() = string(
    "#!/bin/env bash\n",
    "#SBATCH --array=1-6%40\n",
    "#SBATCH --partition=private-kruse-gpu,shared-gpu\n",
    "#SBATCH --time=0-12:00:00\n",
    "#SBATCH --output=%J.out\n",
    "#SBATCH --mem=3000  \n",
    "#SBATCH --gpus=1 \n",
    "#SBATCH --constraint=nvidia_a100-pcie-40gb|nvidia_h100_nvl\n",
    "\n",
    "export use_gpu=true\n",
    "export path_to_data=/srv/beegfs/scratch/users/d/dumoulil/Data/HydraFluids/\$SLURM_ARRAY_TASK_ID/\n",
    "\n",
    "mkdir -p \$path_to_data\n",
    "\n",
    "module load Julia\n",
    "\n",
    "cd \$path_to_data\n",
    "srun julia --optimize=3 /home/users/d/dumoulil/Code/HydraFluids/main.jl\n")
