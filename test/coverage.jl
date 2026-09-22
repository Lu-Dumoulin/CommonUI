# =============================================================================
# Coverage report for utils/, with no dependencies.
#
#   julia --project=. test/coverage.jl            # whole suite
#   julia --project=. test/coverage.jl unit       # one level (same args as runtests.jl)
#
# Runs the suite in a subprocess with coverage limited to utils/, then prints
# a per-file table and the uncovered line numbers, and writes lcov.info at the
# repo root for the VS Code "Coverage Gutters" extension. The notebooks are
# not covered by this suite and are not counted.
#
# Coverage is a conversation starter, not a target (see CLAUDE.md).
# =============================================================================

const ROOT  = normpath(joinpath(@__DIR__, ".."))
const UTILS = joinpath(ROOT, "utils")

covfiles() = filter(f -> occursin(r"\.jl\.\d+\.cov$", f), readdir(UTILS; join = true))

# Merge the per-process .cov files of one source file: for each line,
# `nothing` if it is not executable, otherwise the summed hit count.
function line_counts(src)
    counts = Union{Nothing,Int}[]
    for cov in filter(f -> startswith(basename(f), basename(src) * "."), covfiles())
        for (i, line) in enumerate(eachline(cov))
            field = strip(first(line, 9))
            hits = field == "-" ? nothing : parse(Int, field)
            if i > length(counts)
                push!(counts, hits)
            elseif !isnothing(hits)
                counts[i] = something(counts[i], 0) + hits
            end
        end
    end
    return counts
end

# Julia only instruments methods that get compiled, so a function that is
# never called leaves no counts at all: its lines read as non-executable
# rather than uncovered. Find those from the source instead. Returns the
# (name, first line) of every top-level function definition whose line range
# has no executable line in `counts`.
function never_called(src, counts)
    defs = Tuple{String,Int}[]
    function walk_body(body)
        line = 0
        for ex in body
            ex isa LineNumberNode && (line = ex.line; continue)
            name = def_name(ex)
            isnothing(name) && continue
            # `isloaded() = true`: a literal body has nothing Julia can instrument
            # (it records no hit even when called) and no logic to cover.
            ex.args[2] isa Expr && ex.args[2].head === :block &&
                all(a -> a isa LineNumberNode || !(a isa Expr || a isa Symbol), ex.args[2].args) && continue
            push!(defs, (name, line))
        end
    end
    top = Meta.parseall(read(src, String))
    for ex in top.args
        ex isa Expr && ex.head === :module && walk_body(ex.args[3].args)
    end
    starts = [l for (_, l) in defs]
    missing = Tuple{String,Int}[]
    for (k, (name, line)) in enumerate(defs)
        stop = k < length(defs) ? starts[k+1] - 1 : length(counts)
        span = line:min(stop, length(counts))
        all(i -> isnothing(counts[i]), span) && push!(missing, (name, line))
    end
    return missing
end

# The name defined by `function f(...)`, `f(...) = ...` or `macro m(...)`, else nothing.
function def_name(ex)
    ex isa Expr || return nothing
    if ex.head in (:function, :macro) || (ex.head === :(=) && ex.args[1] isa Expr &&
                                          ex.args[1].head in (:call, :where))
        sig = ex.args[1]
        while sig isa Expr && sig.head === :where
            sig = sig.args[1]
        end
        sig isa Expr && sig.head === :call && return string(sig.args[1])
        return string(sig)
    end
    return nothing
end

# "1-3, 7, 9-10"
function ranges(lines)
    isempty(lines) && return ""
    parts, start, prev = String[], lines[1], lines[1]
    for l in lines[2:end]
        if l == prev + 1
            prev = l
        else
            push!(parts, start == prev ? "$start" : "$start-$prev"); start = prev = l
        end
    end
    push!(parts, start == prev ? "$start" : "$start-$prev")
    return join(parts, ", ")
end

foreach(rm, covfiles())                           # never merge stale runs
cmd = `$(Base.julia_cmd()) --project=$ROOT --startup-file=no --code-coverage=@$UTILS
       $(joinpath(ROOT, "test", "runtests.jl")) $ARGS`
suite_ok = success(pipeline(cmd; stdout, stderr))

sources = sort(filter(f -> endswith(f, ".jl"), readdir(UTILS; join = true)))
report = [(src, line_counts(src)) for src in sources]

println("\nCoverage of utils/ (lines executed / executable lines)\n")
println(rpad("file", 20), lpad("covered", 9), lpad("lines", 7), lpad("%", 7), "   uncovered lines")
total_hit = total_lines = 0
uncalled = Tuple{String,String,Int}[]
for (src, counts) in report
    executable = [i for (i, c) in enumerate(counts) if !isnothing(c)]
    missed = [i for i in executable if counts[i] == 0]
    for (name, line) in never_called(src, counts)
        push!(uncalled, (basename(src), name, line))
        push!(executable, line); push!(missed, line)      # count each as one uncovered line
    end
    sort!(missed)
    hit = length(executable) - length(missed)
    global total_hit += hit; global total_lines += length(executable)
    pct = isempty(executable) ? 100.0 : 100 * hit / length(executable)
    println(rpad(basename(src), 20), lpad(hit, 9), lpad(length(executable), 7),
            lpad(string(round(pct; digits = 1)), 7), "   ", ranges(missed))
end
println(rpad("total", 20), lpad(total_hit, 9), lpad(total_lines, 7),
        lpad(string(round(100 * total_hit / max(total_lines, 1); digits = 1)), 7))

if !isempty(uncalled)
    println("\nNever called (Julia records nothing for these, so they are counted by hand):")
    for (file, name, line) in uncalled
        println("  ", file, ":", line, "  ", name)
    end
end

open(joinpath(ROOT, "lcov.info"), "w") do io
    for (src, counts) in report
        println(io, "SF:", src)
        dead = Set(line for (file, _, line) in uncalled if file == basename(src))
        for (i, c) in enumerate(counts)
            if !isnothing(c)
                println(io, "DA:", i, ",", c)
            elseif i in dead
                println(io, "DA:", i, ",0")
            end
        end
        println(io, "end_of_record")
    end
end
foreach(rm, covfiles())
println("\nWrote lcov.info")
suite_ok || (println("The test suite FAILED; coverage above is from a failing run."); exit(1))
