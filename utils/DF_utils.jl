module DF_utils
using DataFrames, CSV
export generate_dataframe, isloaded

function generate_dataframe(listname, listtab)
    nsim = prod(length.(listtab))
    nsim == 0 && return DataFrame()
    df = DataFrame([name => fill(listtab[i][1], nsim)
                    for (i, name) in enumerate(listname)])
    count = 1
    for (i, name) in enumerate(listname)
        vals = listtab[i]
        if length(vals) > 1
            for j in 1:div(nsim, count)
                df[(j-1)*count+1:j*count, name] .= vals[(j-1) % length(vals) + 1]
            end
            count *= length(vals)
        end
    end
    return df
end

isloaded() = true
end