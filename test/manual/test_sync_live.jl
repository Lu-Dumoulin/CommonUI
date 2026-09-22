# =============================================================================
# MANUAL live-cluster check for SSH_utils.sync against Baobab.
#
# This script talks to the real cluster. It is NOT part of the automated
# suite: test/runtests.jl never includes test/manual/.
#
# HOW TO RUN
#   1. Edit the `usr` line below with your Baobab username.
#   2. Make sure you can `ssh <usr>@login1.baobab.hpc.unige.ch` without being
#      prompted for a password (SSH key set up), otherwise every scp will ask.
#   3. From the repo root:   julia --project=. test/manual/test_sync_live.jl
#
# WHAT IT DOES
#   - creates a tiny dummy tree locally (DF.csv + 1/result.txt + 2/result.txt)
#   - uploads it to a throwaway folder in your scratch
#   - runs SSH_utils.sync four times to check:
#       (1) fresh download into a non-existent folder  -> 3 files
#       (2) immediate re-sync, nothing changed          -> 0 files
#       (3) after `touch`-ing one remote file           -> 1 file
#       (4) parallel download into a fresh folder        -> 3 files
#   - removes the remote test folder and the local temp files at the end.
# =============================================================================

const usr = "dumoulil"
const hst = "login1.baobab.hpc.unige.ch"

include(joinpath(@__DIR__, "..", "..", "utils", "SSH_utils.jl"))

# --- Tiny test harness -------------------------------------------------------
const failures = Ref(0)
function check(name, cond)
    println(cond ? "  [PASS] $name" : "  [FAIL] $name")
    cond || (failures[] += 1)
    return cond
end

usr == "REPLACE_WITH_YOUR_USERNAME" && error("Please set `usr` to your Baobab username at the top of this file.")

# Remote throwaway folder in your scratch, and local temp working dirs.
scratch_root = "/srv/beegfs/scratch/users/$(usr[1])/$usr"
remote_test  = "$scratch_root/CommonUI_sync_test/"
work         = mktempdir()
local_src    = joinpath(work, "src")
local_dst    = joinpath(work, "dst")   # intentionally does NOT exist yet

println("Remote test folder : $usr@$hst:$remote_test")
println("Local temp folder  : $work")
println()

try
    # --- Build the dummy tree locally ----------------------------------------
    mkpath(joinpath(local_src, "1"))
    mkpath(joinpath(local_src, "2"))
    write(joinpath(local_src, "DF.csv"),            "a,b\n1,2\n")
    write(joinpath(local_src, "1", "result.txt"),   "sim 1 output\n")
    write(joinpath(local_src, "2", "result.txt"),   "sim 2 output\n")

    # --- Upload it to scratch -------------------------------------------------
    println("Uploading dummy files to scratch...")
    SSH_utils.mkdir(usr, hst, remote_test)
    SSH_utils.mkdir(usr, hst, "$(remote_test)1")
    SSH_utils.mkdir(usr, hst, "$(remote_test)2")
    SSH_utils.up_file(usr, hst, remote_test,         joinpath(local_src, "DF.csv"))
    SSH_utils.up_file(usr, hst, "$(remote_test)1/",  joinpath(local_src, "1", "result.txt"))
    SSH_utils.up_file(usr, hst, "$(remote_test)2/",  joinpath(local_src, "2", "result.txt"))
    println()

    # --- (1) Fresh download into a non-existent folder -----------------------
    println("[1] Fresh download (local folder does not exist yet)")
    n1 = SSH_utils.sync(usr, hst, remote_test, local_dst)
    check("downloaded all 3 files", n1 == 3)
    check("DF.csv present",          isfile(joinpath(local_dst, "DF.csv")))
    check("1/result.txt present",    isfile(joinpath(local_dst, "1", "result.txt")))
    check("2/result.txt present",    isfile(joinpath(local_dst, "2", "result.txt")))
    check("content matches",         read(joinpath(local_dst, "1", "result.txt"), String) == "sim 1 output\n")
    println()

    # --- (2) Immediate re-sync, nothing changed ------------------------------
    println("[2] Re-sync with no changes")
    n2 = SSH_utils.sync(usr, hst, remote_test, local_dst)
    check("downloaded 0 files (all up-to-date)", n2 == 0)
    println()

    # --- (3) Touch one remote file, then re-sync -----------------------------
    println("[3] Re-sync after touching one remote file")
    SSH_utils.ssh(usr, hst, "touch $(remote_test)1/result.txt")
    n3 = SSH_utils.sync(usr, hst, remote_test, local_dst)
    check("downloaded exactly 1 file", n3 == 1)
    println()

    # --- (4) Parallel download into a fresh folder ---------------------------
    println("[4] Parallel download (nparallel=5) into a fresh folder")
    local_dst2 = joinpath(work, "dst_parallel")
    n4 = SSH_utils.sync(usr, hst, remote_test, local_dst2; nparallel=5)
    check("downloaded all 3 files in parallel", n4 == 3)
    check("2/result.txt present",               isfile(joinpath(local_dst2, "2", "result.txt")))
    println()
finally
    # --- Cleanup, always --------------------------------------------------
    println("Cleaning up...")
    try
        SSH_utils.ssh(usr, hst, "rm -rf $remote_test")
        println("  removed remote $remote_test")
    catch e
        println("  WARNING: could not remove remote folder: $e")
    end
    rm(work; recursive=true, force=true)
    println("  removed local $work")
end

println()
if failures[] == 0
    println("ALL CHECKS PASSED")
else
    println("$(failures[]) CHECK(S) FAILED")
end
