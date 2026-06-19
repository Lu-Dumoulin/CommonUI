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

# ╔═╡ ccd8e669-2024-40e3-8308-e9b9570993aa
import Pkg; Pkg.add(url="https://github.com/Lu-Dumoulin/DataVisualisation.jl")

# ╔═╡ 1ead4d39-e5e7-4117-9e14-dfdcd92be319
using PlutoUI, PlutoTeachingTools, DataVisualisation

# ╔═╡ 5390cff9-e032-438c-b94a-0f75ea5549ac
let
	notebook_path_app = joinpath(@__DIR__, "../../Notebook.pluto.jl")
	notebook_path_run = joinpath(@__DIR__, "RunSimulations.pluto.jl")
	Markdown.parse("You can return to the home page using [this link](./open?path=$notebook_path_app). If you want return to step 2 [click here](./open?path=$notebook_path_run)")
end

# ╔═╡ 482b44fb-a89e-4837-82a9-186cd49d89b9
begin 
	const project_name = splitpath(pwd())[end-2] # "NameOfProject"
@bind csv_path TextField((50,1), default="$(normpath(joinpath(homedir(), "Data/$project_name/DF.csv")))") 
end |> WideCell

# ╔═╡ e482a05e-500b-4361-92b7-5f737b526793
begin
	ws = DataWorkspace(csv_path, ".jld")
	ws.df
end |> WideCell 

# ╔═╡ bc5c65fc-cbaa-4cdf-9c07-44d9a5c58b15
WideCell(md"""
## 3. Data Visualisation
""")

# ╔═╡ 6a2eee21-e6a6-442d-9ab4-e5697ea5a958
WideCell(
md"""
Adapt the dimensions to your screen: scale: $(@bind scale Slider(0.4:0.1:1.0; default=0.5, show_value=true)) and height: $(@bind height Slider(800:100:1800, default=1200, show_value=true))
"""
)

# ╔═╡ 3bf51605-eb94-40ed-b65f-a05ddca608cd
begin

app = explor_app(ws; height="$height px", scale=scale)

end |> WideCell

# ╔═╡ Cell order:
# ╟─ccd8e669-2024-40e3-8308-e9b9570993aa
# ╟─1ead4d39-e5e7-4117-9e14-dfdcd92be319
# ╟─5390cff9-e032-438c-b94a-0f75ea5549ac
# ╠═482b44fb-a89e-4837-82a9-186cd49d89b9
# ╟─e482a05e-500b-4361-92b7-5f737b526793
# ╟─bc5c65fc-cbaa-4cdf-9c07-44d9a5c58b15
# ╟─6a2eee21-e6a6-442d-9ab4-e5697ea5a958
# ╟─3bf51605-eb94-40ed-b65f-a05ddca608cd
