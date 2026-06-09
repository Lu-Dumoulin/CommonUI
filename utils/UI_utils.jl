module UI_utils
using Markdown, PlutoUI, PlutoTeachingTools
export parse_values, named_parse, print_list, parse_to_slurm_array

function parse_to_slurm_array(s::String)
    parts = strip.(split(s, ","))
    filter!(!isempty, parts)
    slurm_parts = []
    for p in parts
        if occursin(":", p)
            tokens = tryparse.(Int, strip.(split(p, ":")))
            if !any(isnothing, tokens)
                # "start:step:stop" → "start:stop:step" (SLURM uses start-stop:step)
                slurm_str = length(tokens) == 3 ? "$(tokens[1])-$(tokens[3]):$(tokens[2])" :
                                                   "$(tokens[1])-$(tokens[2])"
                push!(slurm_parts, slurm_str)
            end
        else
            n = tryparse(Int, p)
            isnothing(n) || push!(slurm_parts, string(n))
        end
    end
    return join(slurm_parts, ",")
end


function parse_values(s::String)
    parts = strip.(split(s, ","))
    filter!(!isempty, parts)
    result = []
    for p in parts
        if occursin(":", p)
            # Parse "start:step:stop" or "start:stop"
            tokens = tryparse.(Float64, strip.(split(p, ":")))
            if !any(isnothing, tokens)
                r = length(tokens) == 3 ? (tokens[1]:tokens[2]:tokens[3]) :
                                          (tokens[1]:tokens[2])
                append!(result, collect(r))
            else
                push!(result, p)  # unparseable, keep as string
            end
        else
            n = tryparse(Float64, p)
            push!(result, isnothing(n) ? p : n)
        end
    end
    return result
end

macro named_parse(expr)
    if isa(expr, Expr) && expr.head === :vect
        actual_args = expr.args
        names  = [replace(string(arg), "_str" => "") for arg in actual_args]
        parsed = map(actual_args) do arg
            if endswith(string(arg), "_str")
                :(Number.(UI_utils.parse_values($arg)))
            else
                arg  # already a value, use as-is
            end
        end
        values_expr = Expr(:vect, parsed...)
        return esc(:( ($values_expr, $names) ))
    else
        error("Syntax error: Please wrap your variables in square brackets, e.g., @named_parse [a_str, zeta, D_str]")
    end
end

function print_list(listname, listvalue)
    if any(isempty, listvalue)
aside(md"""
!!! danger "Alert !"
    One field is empty !
""", v_offset=-250)
else
    for i in eachindex(listname)
        println(listname[i], ": ", listvalue[i])
    end
    md"""
    """
end
end

end