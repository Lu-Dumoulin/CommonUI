### A Pluto.jl notebook ###
# v0.20.28

#> [frontmatter]
#> title = "Run Simulations"
#> date = "2026-05-27"
#> description = "Use this notebook to locally run simulations or to submit the job on slurm cluster."

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 1ead4d39-e5e7-4117-9e14-dfdcd92be319
begin
	using PlutoUI, PlutoTeachingTools, RemoteFiles, OpenSSH_jll, DataFrames, CSV, ProgressLogging
	try
		include("utils/UI_utils.jl")
		@info "Module UI_utils is loaded"
	catch
		try 
			UI_utils.parse_values("1")
			@info "Module UI_utils is already loaded"
		catch
			@error "Error trying to load `utils/UI_utils.jl`. Try to restart the notebook."
		end
	end
	try
		include("utils/SSH_utils.jl")
		@info "Module SSH_utils is loaded"
	catch
		try 
			SSH_utils.isloaded()
			@info "Module SSH_utils is already loaded"
		catch
			@error "Error trying to load `utils/SSH_utils.jl`. Try to restart the notebook."
		end
	end

	if isfile("../sim/DF.csv")
		const Nsim = nrow(CSV.read("../sim/DF.csv", DataFrame))
		@info "Number of simulations = $Nsim"
	else
		@error "You need to generate the DataFrame first !"
	end
	
	const ENUM_GPUs   = ["H100", "A100-40Gb", "A100-80Gb"]

	const project_name = splitpath(pwd())[end-2] # "NameOfProject"
	const sh_name = "$project_name.sh"
	TableOfContents()
end |> WideCell

# ╔═╡ 5390cff9-e032-438c-b94a-0f75ea5549ac
let
	notebook_path_app = joinpath(@__DIR__, "../../Notebook.pluto.jl")
	notebook_path_df = joinpath(@__DIR__, "../GenInputParams.pluto.jl")
	Markdown.parse("You can return to the home page using [this link](./open?path=$notebook_path_app). If you want to modify the DataFrame before starting the simulation(s) [click here](./open?path=$notebook_path_df)")
end |> WideCell

# ╔═╡ bc5c65fc-cbaa-4cdf-9c07-44d9a5c58b15
WideCell(md"""
## 2. Start simulation(s)
""")

# ╔═╡ d014e0b2-cb4c-46ac-9ccf-ca65881fa230
WideCell(md"""
Which simulation do you want to run ? type `all` for all
$(@bind indices_sim_str confirm(TextField(default="1")))

By default the simulations will run locally, do you want to run it on GPU on the cluster (baobab) ? $(@bind clu Switch(default=false)) 

""")

# ╔═╡ abbef949-3312-4305-a80e-21e4c9515b6e
if clu
	md"""
Address of the cluster $(@bind host TextField((50,1),default="login1.baobab.hpc.unige.ch"))

User name: $(@bind username TextField(default="myusername"))

To run the simulations on the cluster the first step is to generate the bash file.
	
1. Partitions: shared-gpu: $(@bind use_shared_gpu Switch(true)), any private partition: $(@bind private_par_str TextField(default="private-kruse-gpu"))
2. Duration of the simulation (default is 0 day and 12h): $(@bind time_str TextField(default="0-12:00:00"))
3. CPU memory (RAM): $(@bind ram_str TextField(default="3000"))
4. Select the gpus to use: $(@bind gpu_list MultiCheckBox(ENUM_GPUs, default=["A100-40Gb", "H100"]))
5. The data will be saved in a your scratch, you can specify a path from the root of your scratch: $(@bind data_path_str TextField((50,1),default=string("/Data/",project_name,"/")))
6. The code will be uploaded in your home folder in $(@bind code_path_str TextField((50,1),default=string("/Code/",project_name,"/")))
	"""
else
	md"""
	By default it would run on CPU using `Threads.jl`, do you want to use the GPU ? $(@bind gpu Switch()).
	"""
end |> WideCell

# ╔═╡ e17bf885-46d3-4f03-b9ce-ff178b4ad6ea
if clu
	array_str = (occursin("all", indices_sim_str) || occursin("All", indices_sim_str) ) ? "1-$Nsim%40" : UI_utils.parse_to_slurm_array(indices_sim_str)
	partition_str = use_shared_gpu ? string(private_par_str,",shared-gpu") : private_par_str
	gpu_str = string( [ i=="A100-40Gb" ? "nvidia_a100-pcie-40gb|" : (i=="H100" ? "nvidia_h100_nvl|" : "nvidia_a100_80gb_pcie|") for i in gpu_list]...  )[1:end-1]
		default_bash_str = """
#!/bin/env bash
#SBATCH --array=$array_str
#SBATCH --partition=$partition_str
#SBATCH --time=$time_str
#SBATCH --output=%J.out
#SBATCH --mem=3000  
#SBATCH --gpus=1 
#SBATCH --constraint=$gpu_str

export use_gpu=true
export path_to_data=/srv/beegfs/scratch/users/$(username[1])/$username$data_path_str

mkdir -p \$path_to_data

module load Julia

cd \$path_to_data
srun julia --optimize=3 /home/users/$(username[1])/$username$(code_path_str)main.jl
		"""
	md"""
bash file:
		
$(@bind bash_string TextField((100,20),default=default_bash_str))
	"""
else
	cpu_str = !gpu ? " -t auto" : ""
	local_main_normpath = "../sim/main.jl" #normpath(joinpath(@__DIR__,"../sim/main.jl"))
	list_of_sim = isempty(indices_sim_str) ? [1] : ((occursin("all", indices_sim_str) || occursin("All", indices_sim_str) ) ? (1:Nsim) : Int.(UI_utils.parse_values(indices_sim_str)))
	cmd = "julia --optimize=3$(cpu_str) $local_main_normpath";
	@show gpu; @show list_of_sim; @show cmd
md""" 
In which folder do you want to save the data ? 
$(@bind path_to_data TextField((100,1),default=string(homedir()*"/Data/",project_name,"/")))
	
In which folder do you want to save the output files (stdout) ?
$(@bind path_to_out TextField((100,1),default=string(normpath(joinpath(@__DIR__,"../../out/")))))
	
The following code of Julia will be executed on button press, this runs simulations sequentially."""
end |> WideCell

# ╔═╡ 120d6803-30c3-4950-a9b3-066574feacda
if clu
	md"""
Switch to continue: $(@bind continue_bash Switch()). 
	
The bash will be saved as $(sh_path = normpath(@__DIR__,"../sim/")). 
	
The code necessary to run the simulations will be upload on the cluster using `ssh`.

An other confirmation will be required to run simulations. 
"""
else
	@show path_to_out; @show path_to_data
	md"""
```julia
mkpath(path_to_out)
for i in list_of_sim
	println("Running job $i")
	data_path = joinpath(path_to_data,"$i/") 
	withenv("SLURM_ARRAY_TASK_ID" => string(i),
			"path_to_data" => data_path,
			"use_gpu" => gpu) do
		run(
			pipeline
			(
				Cmd(Cmd(split(cmd))), stdout=joinpath(path_to_out,"out_$i.txt")
			)
		)
	end
end
```
If you continue, the simulations will start.
Switch to continue: $(@bind continue_local Switch())
"""
end |> WideCell

# ╔═╡ dc7fbcdf-790b-473f-a738-7558c14b0ba8
if clu
	if continue_bash
		open(string(sh_path,sh_name), "w") do file
			write(file, bash_string)
		end
		println(" Bash saved in $sh_path as $sh_name ")
	end
else
	if continue_local
		mkpath(path_to_out)
		cp("../sim/DF.csv", path_to_data*"DF.csv", force=true)
		@progress for i in list_of_sim
			println("Running job $i")
			data_path = joinpath(path_to_data,"$i/") 
			withenv("SLURM_ARRAY_TASK_ID" => string(i),
					"path_to_data" => data_path,
					"use_gpu" => gpu) do
				@info run(
					pipeline(
						Cmd(Cmd(split(cmd))), stdout=joinpath(path_to_out,"out_$i.txt")
					)
				)
			end
		end
	end
end;

# ╔═╡ 16a91e7a-9ca7-452b-93cb-ce9a2b6476d3
if clu && continue_bash
	local_code_path = normpath(joinpath(@__DIR__, "../sim/"))*"."
	path_to_code = string("/home/users/$(username[1])/$username",code_path_str)
	path_to_data_folder = string("/srv/beegfs/scratch/users/$(username[1])/$username",data_path_str)

	println("Create $path_to_code on $username@$host")
	SSH_utils.mkdir(username, host, path_to_code)
	println()
	println("Create $path_to_data_folder on $username@$host")
	SSH_utils.mkdir(username, host, path_to_data_folder)
	println()
	
	println("Upload code from ", local_code_path, " to ", path_to_code, "on $username@$host")
	SSH_utils.up_dir(username, host, path_to_code, local_code_path)
	list_of_file_clu_code = SSH_utils.readdir(username, host, path_to_code)
	println()
	println("The following files have been uploaded")
	for file in list_of_file_clu_code
		println("       ", file)
	end
	
	SSH_utils.print_ssh(username, host, "cd $path_to_data_folder")# && sbatch $sh_name")
	SSH_utils.print_ssh(username, host, "squeue --me") 
	md"""
	"""
else
	if !clu 
		let
			notebook_path_visu = joinpath(@__DIR__, "DataVisualisation.pluto.jl")
			Markdown.parse("Once the jld/jld2 files are saved, you can use [this link](./open?path=$notebook_path_visu) to visualise the data.")
		end
	else
	md"""
	"""
	end
end |> WideCell

# ╔═╡ 08ca3f40-0135-46fc-85be-6b1b3fed0acd
if clu
	remote_data_folder = string("/srv/beegfs/scratch/users/$(username[1])/$username",
		endswith(data_path_str, "/") ? data_path_str : data_path_str * "/")
	md"""
## 3. Download data

The simulation results are stored on your scratch at `$remote_data_folder`.

Local destination folder: $(@bind local_data_path TextField((100,1),default=string(homedir(),"/Data/",project_name,"/")))

Number of files to download in parallel: $(@bind nparallel Slider(1:10; default=4, show_value=true))

Switch to download the data from the cluster: $(@bind continue_download Switch())

Only files that are **missing locally or newer on the cluster** are downloaded, so you can re-run this while simulations are still producing output.
	"""
else
	md"""
	"""
end |> WideCell

# ╔═╡ 7d2c5e1a-9b34-4e6f-8a01-3c4d5e6f7a8b
if clu && continue_download
	mkpath(local_data_path)
	println("Sync data from $username@$host:$remote_data_folder")
	println("            to $local_data_path")
	println()
	SSH_utils.sync(username, host, remote_data_folder, local_data_path; nparallel=nparallel)
	md"""
	"""
else
	md"""
	"""
end |> WideCell

# ╔═╡ 11b767b5-db54-45f3-855a-2e75f3936e7c
if clu 
	let
	notebook_path_visu = joinpath(@__DIR__, "DataVisualisation.pluto.jl")
	Markdown.parse("Once the jld/jld2 files are saved, you can use [this link](./open?path=$notebook_path_visu) to visualise the data.")
	end
else
	md"""
	"""
end |> WideCell

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
OpenSSH_jll = "9bd350c2-7e96-507f-8002-3f2e150b4e1b"
PlutoTeachingTools = "661c6b06-c737-4d37-b85c-46df65de6f69"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
ProgressLogging = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
RemoteFiles = "cbe49d4c-5af1-5b60-bb70-0a60aa018e1b"

[compat]
CSV = "~0.10.16"
DataFrames = "~1.8.2"
OpenSSH_jll = "~10.3.1"
PlutoTeachingTools = "~0.4.7"
PlutoUI = "~0.7.81"
ProgressLogging = "~0.1.6"
RemoteFiles = "~0.5.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.6"
manifest_format = "2.0"
project_hash = "24546df8d1ba705b1eaac9b17c84df931103dd87"

[[deps.AbstractPlutoDingetjes]]
git-tree-sha1 = "6c3913f4e9bdf6ba3c08041a446fb1332716cbc2"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.4.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.BitFlags]]
git-tree-sha1 = "0691e34b3bb8be9307330f88d1a3c3f25466c24d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.9"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "PrecompileTools", "SentinelArrays", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "8d8e0b0f350b8e1c91420b5e64e5de774c2f0f4d"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.16"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "962834c22b66e32aa10f7611c08c8ca4e20749a9"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.8"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "67e11ee83a43eb71ddc950302c53bf33f0690dfe"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.12.1"
weakdeps = ["StyledStrings"]

    [deps.ColorTypes.extensions]
    StyledStringsExt = "StyledStrings"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "9d8a54ce4b17aa5bdce0ea5c34bc5e7c340d16ad"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.18.1"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.0+1"

[[deps.ConcurrentUtilities]]
deps = ["Serialization", "Sockets"]
git-tree-sha1 = "21d088c496ea22914fe80906eb5bce65755e5ec8"
uuid = "f0e56b4a-5159-44fe-b623-3e5288b988bb"
version = "2.5.1"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "DataStructures", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrecompileTools", "PrettyTables", "Printf", "Random", "Reexport", "SentinelArrays", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "5fab31e2e01e70ad66e3e24c968c264d1cf166d6"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.8.2"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "e357641bb3e0638d353c4b29ea0e40ea644066a6"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.3"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.7.0"

[[deps.ExceptionUnwrapping]]
deps = ["Test"]
git-tree-sha1 = "d36f682e590a83d63d1c7dbd287573764682d12a"
uuid = "460bff9d-24e4-43bc-9d9f-a8973cb893f4"
version = "0.1.11"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "8e9c059d6857607253e837730dbf780b6b151acd"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.19.0"
weakdeps = ["HTTP"]

    [deps.FileIO.extensions]
    HTTPExt = "HTTP"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates"]
git-tree-sha1 = "3bab2c5aa25e7840a4b065805c0cdfc01f3068d2"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.24"
weakdeps = ["Mmap", "Test"]

    [deps.FilePathsBase.extensions]
    FilePathsBaseMmapExt = "Mmap"
    FilePathsBaseTestExt = "Test"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "05882d6995ae5c12bb5f36dd2ed3f61c98cbb172"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.5"

[[deps.Format]]
git-tree-sha1 = "9c68794ef81b08086aeb32eeaf33531668d5f5fc"
uuid = "1fa38f19-a742-5d3f-a2b9-30dd87b9d5f8"
version = "1.3.7"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"
version = "1.11.0"

[[deps.Ghostscript_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Zlib_jll"]
git-tree-sha1 = "38044a04637976140074d0b0621c1edf0eb531fd"
uuid = "61579ee1-b43e-5ca0-a5da-69d92c66a64b"
version = "9.55.1+0"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "ConcurrentUtilities", "Dates", "ExceptionUnwrapping", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "PrecompileTools", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "51059d23c8bb67911a2e6fd5130229113735fc7e"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.11.0"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "d1a86724f81bcd184a38fd284ce183ec067d71a0"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "1.0.0"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "0ee181ec08df7d7c911901ea38baf16f755114dc"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "1.0.0"

[[deps.InlineStrings]]
git-tree-sha1 = "8f3d257792a522b4601c24a577954b0a8cd7334d"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.5"

    [deps.InlineStrings.extensions]
    ArrowTypesExt = "ArrowTypes"
    ParsersExt = "Parsers"

    [deps.InlineStrings.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"
    Parsers = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.InvertedIndices]]
git-tree-sha1 = "6da3c4316095de0f5ee2ebd875df8721e7e0bdbe"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.1"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "c0c9b76f3520863909825cbecdef58cd63de705a"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "3.1.5+0"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "dda21b8cbd6a6c40d9d02a73230f9d70fed6918c"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.4.0"

[[deps.Latexify]]
deps = ["Format", "Ghostscript_jll", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "OrderedCollections", "Requires"]
git-tree-sha1 = "44f93c47f9cd6c7e431f2f2091fcba8f01cd7e8f"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.16.10"

    [deps.Latexify.extensions]
    DataFramesExt = "DataFrames"
    SparseArraysExt = "SparseArrays"
    SymEngineExt = "SymEngine"
    TectonicExt = "tectonic_jll"

    [deps.Latexify.weakdeps]
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    SymEngine = "123dc426-2d89-5057-bbad-38513e3affd8"
    tectonic_jll = "d7dd28d6-a5e6-559c-9131-7eb760cdacc5"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.15.0+0"

[[deps.LibGit2]]
deps = ["LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"
version = "1.11.0"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.9.0+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "OpenSSL_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.3+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.12.0"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "f00544d95982ea270145636c181ceda21c4e2575"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.2.0"

[[deps.MIMEs]]
git-tree-sha1 = "c64d943587f7187e751162b3b84445bbbd79f691"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.1.0"

[[deps.MacroTools]]
git-tree-sha1 = "1e0228a030642014fe5cfe68c2c0a818f9e3f522"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.16"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "NetworkOptions", "Random", "Sockets"]
git-tree-sha1 = "8785729fa736197687541f7053f6d8ab7fc44f92"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.10"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "ff69a2b1330bcb730b9ac1ab7dd680176f5896b8"
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.1010+0"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "ec4f7fbeab05d7747bdf98eb74d130a2a2ed298d"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.2.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2025.11.4"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.3.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.29+0"

[[deps.OpenSSH_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "OpenSSL_jll", "Zlib_jll"]
git-tree-sha1 = "57baa4b81a24c2910afbb6d853aa0685e4312bf7"
uuid = "9bd350c2-7e96-507f-8002-3f2e150b4e1b"
version = "10.3.1+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "NetworkOptions", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "1d1aaa7d449b58415f97d2839c318b70ffb525a0"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.6.1"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.5.4+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "05868e21324cede2207c6f0f466b4bfef6d5e7ee"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.8.1"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "5d5e0a78e971354b1c7bff0655d11fdc1b0e12c8"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.4"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "Random", "SHA", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.12.1"
weakdeps = ["REPL"]

    [deps.Pkg.extensions]
    REPLExt = "REPL"

[[deps.PlutoTeachingTools]]
deps = ["Downloads", "HypertextLiteral", "Latexify", "Markdown", "PlutoUI"]
git-tree-sha1 = "90b41ced6bacd8c01bd05da8aed35c5458891749"
uuid = "661c6b06-c737-4d37-b85c-46df65de6f69"
version = "0.4.7"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Downloads", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "79436d2d6f29a5d5b4e4749043a3f190d55631a3"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.81"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "36d8b4b899628fb92c2749eb488d884a926614d3"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.3"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "edbeefc7a4889f528644251bdb5fc9ab5348bc2c"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.3.4"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "8b770b60760d4451834fe79dd483e318eee709c4"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.5.2"

[[deps.PrettyTables]]
deps = ["Crayons", "LaTeXStrings", "Markdown", "PrecompileTools", "Printf", "REPL", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "624de6279ab7d94fc9f672f0068107eb6619732c"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "3.3.2"

    [deps.PrettyTables.extensions]
    PrettyTablesTypstryExt = "Typstry"

    [deps.PrettyTables.weakdeps]
    Typstry = "f0ed7684-a786-439e-b1e3-3b82803b501e"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.ProgressLogging]]
deps = ["Logging", "SHA", "UUIDs"]
git-tree-sha1 = "f0803bc1171e455a04124affa9c21bba5ac4db32"
uuid = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
version = "0.1.6"

[[deps.REPL]]
deps = ["InteractiveUtils", "JuliaSyntaxHighlighting", "Markdown", "Sockets", "StyledStrings", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RemoteFiles]]
deps = ["Dates", "FileIO", "HTTP"]
git-tree-sha1 = "9a0241c411af313068188e89ebf322cb49eedf52"
uuid = "cbe49d4c-5af1-5b60-bb70-0a60aa018e1b"
version = "0.5.0"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "62389eeff14780bfe55195b7204c0d8738436d64"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.1"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "084c47c7c5ce5cfecefa0a98dff69eb3646b5a80"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.10"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "f305871d2f381d21527c770d4788c06c097c9bc1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.2.0"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"
version = "1.11.0"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "64d974c2e6fdf07f8155b5b2ca2ffa9069b608d9"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.2"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

    [deps.Statistics.weakdeps]
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.StringManipulation]]
deps = ["PrecompileTools"]
git-tree-sha1 = "d05693d339e37d6ab134c5ab53c29fce5ee5d7d5"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.4.4"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "f2c1efbc8f3a609aadf318094f8fc5204bdaf344"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.12.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.TranscodingStreams]]
git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.11.3"

[[deps.Tricks]]
git-tree-sha1 = "311349fd1c93a31f783f977a71e8b062a57d4101"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.13"

[[deps.URIs]]
git-tree-sha1 = "bef26fb046d031353ef97a82e3fdb6afe7f21b1a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.6.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "0716e01c3b40413de5dedbc9c5c69f27cddfddfc"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.3"

[[deps.WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.64.0+1"

[[deps.p7zip_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.7.0+0"
"""

# ╔═╡ Cell order:
# ╟─1ead4d39-e5e7-4117-9e14-dfdcd92be319
# ╟─5390cff9-e032-438c-b94a-0f75ea5549ac
# ╟─bc5c65fc-cbaa-4cdf-9c07-44d9a5c58b15
# ╟─d014e0b2-cb4c-46ac-9ccf-ca65881fa230
# ╟─abbef949-3312-4305-a80e-21e4c9515b6e
# ╟─e17bf885-46d3-4f03-b9ce-ff178b4ad6ea
# ╟─120d6803-30c3-4950-a9b3-066574feacda
# ╟─dc7fbcdf-790b-473f-a738-7558c14b0ba8
# ╟─16a91e7a-9ca7-452b-93cb-ce9a2b6476d3
# ╟─08ca3f40-0135-46fc-85be-6b1b3fed0acd
# ╟─7d2c5e1a-9b34-4e6f-8a01-3c4d5e6f7a8b
# ╟─11b767b5-db54-45f3-855a-2e75f3936e7c
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
