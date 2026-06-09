module SSH_utils
using RemoteFiles, OpenSSH_jll

export ssh, print_ssh, down, up, up_dir, up_file, mkdir, isloaded

ssh(usr, hst, cmd) = readchomp(`ssh $usr\@$hst $cmd`)

print_ssh(usr, hst, cmd) =  println(ssh(usr, hst, cmd))

down(usr, hst, cluster_file_path, local_directory_path) = run(`scp -r $usr\@$hst:$cluster_file_path $local_directory_path`)

up(usr, hst, cluster_directory_path, local_file_path) = run(`scp -r $local_file_path $usr\@$hst:$cluster_directory_path`)
up_dir(usr, hst, cluster_directory_path, local_directory_path) = run(`scp -r """$local_directory_path""" $usr\@$hst:$cluster_directory_path`)
up_file(usr, hst, cluster_directory_path, local_file_path) = run(`scp $local_file_path $usr\@$hst:$cluster_directory_path`);

function mkdir(u, h, cluster_directory_path)
    if ssh(u, h, "test -d $cluster_directory_path  && echo true || test ! -d $cluster_directory_path") == "true"
        println("$cluster_directory_path exists")
    else
        ssh(u, h, "mkdir -p $cluster_directory_path")
        println("Create $cluster_directory_path")
    end
end

readdir(u, h, cluster_directory_path) = split(ssh(u, h, "ls $cluster_directory_path"), "\n", keepempty=false)

isloaded() = true

end
# export ssh, run_ssh, ssh_print, cluster_home_path, cluster_scratch_path

# cluster_home_path(username) = "/home/users/$(username[1])/$username/"
# cluster_scratch_path(username) = "/srv/beegfs/scratch/users/$(username[1])/$username/"

# # const local_utilities_path = normpath(string(@__DIR__,"/"))

# # Little function to execute a commande using SSH on the cluster
# run_ssh(username, host, cmd) = run(`ssh $username\@$host $cmd`)
# # Same but return consol as a string
# ssh(username, host, cmd) = readchomp(`ssh $username\@$host $cmd`)
# # Same but print result
# ssh_print(username, host, cmd) =  println(ssh(username, host, cmd))


# ############### File Managment ###############
# module File
# using ..SSH

# @inline readdir(u, h, cluster_directory_path) = split(ssh(u, h, "ls $(cluster_directory_path(u))"), "\n", keepempty=false)

# @inline findfile(u, h, filename, cluster_directory_path) = ssh(u, h, "find $(cluster_directory_path(u)) -name $filename")

# @inline function isfile(u, h, cluster_file_path)
#     local answ;
#     try
#         answ = ssh(u, h, """[[ -f $cluster_file_path ]] && echo "1" || echo "0" """)
#     catch
#         answ = "Issue"
#     end
#     answ == "1" ? (return true) : nothing
#     if answ == "0"
#         return false
#     else 
#         println(" ERROR while looking for $cluster_file_path")
#         return false
#     end
# end

# @inline function isdir(u, h, dir_name)
#     full_path = cluster_home_path(u)*dir_name
#     full_path *= endswith("/", full_path) ? "" : "/"
#     local answ;
#     try
#         answ = ssh(u, h, """ [ -d $full_path ]  && echo "1" || echo "0" """)
#     catch
#         answ = "Issue"
#     end
#     answ == "1" ? (return true) : nothing
#     if answ == "0"
#         return false
#     else 
#         println(" ERROR while looking for $full_path")
#         return false
#     end
# end

# @inline function filesize(u, h, cluster_file_path)
#     try
#         return tryparse(Int, ssh(u, h, `stat --printf="%s" $cluster_file_path`))
#     catch
#         return 0
#     end
# end

# @inline function mkdir(u, h, cluster_directory_path)
#     if ssh(u, h, "test -d $cluster_directory_path  && echo true || test ! -d $cluster_directory_path") == "true"
#         println("$cluster_directory_path exists")
#     else
#         ssh(u, h, "mkdir -p $cluster_directory_path")
#         println("Create $cluster_directory_path")
#     end
# end
# end

# ############### Print informations ###############
# module Print
# export quota, infogpus, seff, squeue, scancel, out, lastout, get_list_nodes, infonodes
# using ..SSH, .SSH.Get

# quota(u, h) = ssh_print(u, h, "beegfs-get-quota-home-scratch.sh $u")

# squeue(u, h; opt="") = ssh_print(u, h, "squeue -u $u $opt")
# seff(u, h, jobID) = ssh_print(u, h, "seff $jobID")

# scancel(u, h, num) = ssh_print(u, h, "scancel "*string(num))

# end


# ############### Download/upload ###############
# module SCP
# using ..SSH, .SSH.file

# @inline filter_ext!(list_of_file, ext) = filter!(endswith(ext), list_of_file)
# @inline filter_ext(list_of_file, ext) = filter(endswith(ext), list_of_file)

# @inline down(u, h, cluster_file_path, local_directory_path) = run(`scp -r $u\@$h:$cluster_file_path $local_directory_path`)

# @inline up(u, h, cluster_directory_path, local_file_path) = run(`scp -r $local_file_path $u\@$h:$cluster_directory_path`)

# @inline up_dir(u, h, cluster_directory_path, local_directory_path) = run(`scp """$local_directory_path""""*" $u\@$h:$cluster_directory_path`)

# @inline up_file(u, h, cluster_directory_path, local_file_path) = run(`scp $local_file_path $u\@$h:$cluster_directory_path`)

# @inline function up_ext(u, h, cluster_directory_path, local_directory_path, ext)
#     for i in filter_ext!(readdir(local_directory_path), ext)
#         up_file(u, h, cluster_directory_path, local_directory_path*i)
#     end
# end

# @inline up_jl(u, h, cluster_directory_path, local_directory_path) = up_ext(u, h, cluster_directory_path, local_directory_path, ".jl")

# @inline function update_file(u, h, filename, cluster_directory_path, local_directory_path)
#     if filename != "" && File.filesize(u, h, cluster_directory_path*filename) != filesize(local_directory_path*filename)
#         println(" update $u\@$h:$(cluster_directory_path*filename) to $(local_directory_path*filename)")
#         down(u, h, cluster_directory_path*filename, local_directory_path)
#     end
# end

# # Fonction that update file(s) of a specific ext (".something" file(s)) 
# # of your local dir if the file on the cluster is different (in size)
# function update_ext(u, h, cluster_directory_path, local_directory_path, ext=".out")
#     for filename in filter_ext!(File.readdir(u, h, cluster_directory_path), ext)
#        update_file(u, h, filename, cluster_directory_path, local_directory_path)
#     end
# end

# # Recursive function that download files of cluster directory (cdir) on your computer (ldir)
# # Only if the files on the computer do not exist
# function download_dir(u, h, cluster_directory_path, local_directory_path)
#     isfile(local_directory_path[1:end-1]) && return nothing
#     isdir(local_directory_path) ? nothing : mkpath(local_directory_path)
#     list_of_local_subdirectories = readdir(local_directory_path)
#     list_of_subdirectories = File.readdir(u, h, cluster_directory_path)
#     for subdirectory in list_of_subdirectories
#         o = findfirst(subdirectory .== list_of_local_subdirectories)
#         if isnothing(o)
#             println(" Copy $u$h:$cluster_directory_path$subdirectory into $local_directory_path")
#             down(u, h, cluster_directory_path*subdirectory, local_directory_path)
#         else
#             download_dir(u, h, cluster_directory_path*subdirectory*"/", local_directory_path*subdirectory*"/")
#         end
#     end
# end

# # Call download_dir and upate_ext for specific extension
# # This function needs to be edited according to your need
# function download(u, h, cluster_directory, local_directory_path)
#     cluster_directory_path = (startswith(cluster_directory, "/home/") || startswith(cluster_directory, "/srv")) ? cluster_directory : cluster_home_path*cluster_directory
#     println("Download $cluster_directory_path into $local_directory_path")
#     mkpath(local_directory_path)
#     update_ext(u, h, cluster_directory_path, local_directory_path, ".csv")
#     update_ext(u, h, cluster_directory_path, local_directory_path, ".out")
#     download_dir(u, h, cluster_directory_path, local_directory_path)
# end
# end
# end
