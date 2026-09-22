module DF_utils
using DataFrames, CSV
export generate_dataframe, isloaded

# Full-factorial sweep: one row per combination of values. The FIRST parameter
# varies fastest and the last slowest; row i of DF.csv is SLURM_ARRAY_TASK_ID i,
# so this ordering is a contract (see test/unit/test_df_utils.jl).
function generate_dataframe(listname, listtab)
    length(listname) == length(listtab) || throw(ArgumentError(
        "generate_dataframe: got $(length(listname)) parameter names but $(length(listtab)) value lists"))
    any(isempty, listtab) && return DataFrame()
    rows = vec(collect(Iterators.product(listtab...)))   # product varies its first argument fastest
    return DataFrame([name => [row[i] for row in rows] for (i, name) in enumerate(listname)])
end

isloaded() = true
end
