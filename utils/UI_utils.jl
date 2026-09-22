module UI_utils
using Markdown, PlutoUI, PlutoTeachingTools
export parse_values, named_parse, print_list, parse_to_slurm_array

# --- Shared tokenizer ---------------------------------------------------------
# Both parsers read the same mini-language: comma-separated tokens, blanks
# dropped, each token either a plain value or a range `a:b` / `a:b:c`
# (start:step:stop). `split_tokens` decides what each token is; the parsers
# decide what to do with it.

# A range token whose fields all parsed as T; `step` is `nothing` for `a:b`.
# `text` is the token as the user typed it, for error messages.
struct RangeToken{T}
    start::T
    step::Union{T,Nothing}
    stop::T
    text::String
end

# Returns a vector whose elements are a parsed `T`, a `RangeToken{T}`, or the
# raw token (an AbstractString) when it does not parse as T. A range whose
# fields all parse but has more than three of them is an error.
function split_tokens(s::AbstractString, ::Type{T}) where {T<:Real}
    tokens = Any[]
    for p in filter!(!isempty, strip.(split(s, ",")))
        if occursin(":", p)
            fields = tryparse.(T, strip.(split(p, ":")))
            if any(isnothing, fields)
                push!(tokens, p)
            elseif length(fields) > 3
                throw(ArgumentError("range \"$p\" has $(length(fields)) fields; expected a:b or a:b:c"))
            else
                push!(tokens, length(fields) == 3 ? RangeToken{T}(fields[1], fields[2], fields[3], p) :
                                                    RangeToken{T}(fields[1], nothing, fields[2], p))
            end
        else
            n = tryparse(T, p)
            push!(tokens, isnothing(n) ? p : n)
        end
    end
    return tokens
end

# Slurm `--array` spec: integers only; anything that is not an integer is
# silently dropped. "start:step:stop" renders as SLURM's "start-stop:step".
function parse_to_slurm_array(s::String)
    slurm_parts = String[]
    for tok in split_tokens(s, Int)
        if tok isa RangeToken
            step = something(tok.step, 1)
            (step >= 1 && tok.start <= tok.stop) || throw(ArgumentError(
                "parse_to_slurm_array: range \"$(tok.text)\" must count up with a positive step"))
            push!(slurm_parts, isnothing(tok.step) ? "$(tok.start)-$(tok.stop)" :
                                                     "$(tok.start)-$(tok.stop):$(tok.step)")
        elseif tok isa Int
            push!(slurm_parts, string(tok))
        end
    end
    return join(slurm_parts, ",")
end


# Parameter values: numbers come back as Float64, ranges are expanded, and
# unparseable tokens pass through as strings. Returns a Vector{Any} on purpose:
# the notebook's `Number.(...)` then fails loudly on bad input.
function parse_values(s::String)
    result = []
    for tok in split_tokens(s, Float64)
        if tok isa RangeToken
            r = isnothing(tok.step) ? (tok.start:tok.stop) : (tok.start:tok.step:tok.stop)
            isempty(r) && throw(ArgumentError("parse_values: range \"$(tok.text)\" contains no values"))
            append!(result, collect(r))
        else
            push!(result, tok)
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