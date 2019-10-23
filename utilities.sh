#! /bin/bash -

update_status(){
    # This script reports the state of a current
    # file hash update.
    dir="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
    lockFile="$dir/update_file_hashes.lock"
    printf -v esc '\e'
    if [[ ! -f "$lockFile" ]]; then
        printf "Currently there is no update running.\n"
        return
    fi
    sed "s/^[^:]*:/${esc}[34m&${esc}[0m/g" "$lockFile"
    slurmID=$(sed -n 's/Slurm Job ID: \(.*\)$/\1/p' "$lockFile")
    if [[ ! -z $slurmID ]]; then
        filter="JobName: \|RunTime: \|TimeLimit: \|SubmitTime: \|StartTime: "
        scontrol -o show job $slurmID | \
            sed "s/\([^ ,]*\)=/\x0${esc}[34m\1: ${esc}[0m/g" | \
            grep -z "$filter" | tr '\0' '\n'
    fi
    progFile=$(sed -n 's/Progress: \(.*\)$/\1/p' "$lockFile")
    if [[ ! -f "$progFile" ]]; then
        printf "There is no progress file\e[33m %s\e[0m\n" "$progFile"
        return
    fi
    tail -n1 "$progFile" | sed "s/.*/${esc}[32m&${esc}[0m/g"
}

get_running(){
    # Returns running slurm jobs for the current directory.
    dir="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
    squeue -h -o "%i/%Z//" "$@" | grep -F "/$dir//" | \
        cut -d/ -f1 | tr '\n' ':' | head -c-1
}

slurm_submit(){
    # Usage: slurm_submit <script>
    # Submitts slurm <script> as slurm job that
    # runs after other jobs in the same working directory
    # finished and tracks the output log.
    dir="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
    script_name="$(basename "$(readlink -f "$1")")"
    running="$(get_running)"
    if [[ -z $running ]]; then
        unset slurm_deps
    else
        printf 'Currently running:\n'
        update_status
        printf 'Running after job(s)\e[33m %s\e[0m.\n' "$running"
        slurm_deps="afterany:$running"
    fi
    slurmLog="$dir/update_logs/${script_name}.$(date +%s).slurm"
    mkdir -p "$(dirname "$slurmLog")"
    export slurmLog

    slurmID=$(sbatch --dependency="$slurm_deps" \
        -D "$dir" --out="$slurmLog" --export=ALL \
        -- "$1" --prepared "${@:2}")
    slurmID="${slurmID##* }"
    printf 'Submitted Slurm Job with ID\e[34m %s\e[0m\n' "$slurmID"
    [[ -t 0 ]] || exit # exit if not a terminal
    printf 'Waiting for output in\e[33m %s\e[0m ...\n' "$slurmLog"
    printf 'Press (Crtl + C) to cancle watching.'
    printf ' The job will continue anyway.\n'
    trap "exit 0" INT TERM
    sleep 2
    while [[ ! -f "$slurmLog" ]]; do sleep 10; done
    tail -n+1 -f "$slurmLog" &
    trap "kill -PIPE $!
        printf '\rQuitting to watch\e[33m %s\e[0m ...\n' \"$slurmLog\"
        exit 0" EXIT
    srun --job-name="waiting for $slurmID" --dependency="afterany:$slurmID" \
        --mem=1 --cpus-per-task=1 --ntasks=1 --time=0-00:00:01 sleep 0 &> /dev/null
}

sub_remove()(
    # Usage: sub_remove <input> [<#threads>] [--delete]
    # Removes all subdirect within <input> with format
    # <size>,<hash>,<path>
    # If "--delete" is passed as 3rd argument then <input>
    # is deleted as soon as possible to safe memory.
    export LC_ALL=C # byte-wise sorting
    (($#>0)) && inFile="$1" || inFile="-"
    (($#>1)) && nthreads="$2" || nthreads=$(nproc)
    (($#>2)) && [[ "$3" == "--delete" ]] && DEL=TRUE || DEL=FALSE
    tempOut=$(mktemp)
    ltrapF(){
        rm -r $tempOut 2> /dev/null
        exit
    }
    trap ltrapF EXIT RETURN
    sort -t , -k3 -u -o $tempOut "$inFile"
    [[ $DEL == TRUE ]] && rm "$inFile"
    extract(){
        PATTERN="//"
        while read line; do
            if [[ ! "$line" =~ ",$PATTERN" ]]; then
                printf '%s\n' "$line"
                PATTERN="${line#*,*,}"
            fi
        done
    }
    if (($(du -BM $tempOut | cut -dM -f1)<20)); then
        extract < $tempOut
        return
    fi
    export -f extract
    parallel --will-cite --pipepart -a $tempOut --block 10M -k -j "$nthreads" \
        extract | extract
)

rmColor(){
    # Removes ansi terminal colors from text when piped through.
    sed -r "s/[[:cntrl:]]\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
}

sortByPath()(
    # Usage: sortByPath <input> > <output>
    # Reformats a file with the line format
    # <size>,<hash>,<path>
    # to
    # <path>,<size>,<hash>
    # and sorts the lines bite-wise. This format enables
    # `look` to search the output by path and
    # is prerequisit for `make_dir_hashes` and `du`.
    export LC_ALL=C # byte-wise sorting
    [[ -z "$SortBuffer" ]] && SortBuffer="80%"
    parallel --will-cite --pipepart -a "$*" \
        "grep -va '^#\|^%' | sed 's/^\([^,]*,[^,]*\),\(.*\)$/\2,\1/g'" | \
        sort -S "$SortBuffer"
)

sizeHashSort(){
    # This function sorts from large to small numeric values in the first
    # column seperated by "," and in in increasing oder of the other columns.
    export LC_ALL=C # byte-wise sorting
    [[ -z "$SortBuffer" ]] && SortBuffer="80%"
    sort --parallel=$sortThreads -S $SortBuffer -t , -k1,1rn -k2,3 -u
 }

hashThat()(
    # Usage: hashThat <dir1> <dir2> ...
    # Imports the function hashThat that hashes all
    # files in the given directories to the format
    # of hashdeep.
    searchDirString=$(printf '"%s" ' "${@//\"/\\\"}")
    BLACK=$(sed "s/^/-path /g" "$dir/blacklist" | \
        sed -e ':a; N; $!ba; s/\n/ -o /g')
    fCommand="find $searchDirString \( $BLACK \) -prune -o -type f -print0"

    makeHash(){
        timeout 600 head -c 1 "$@" > /dev/null
        case "$?" in
            "0")
                SIZE=$(stat --printf='%s' "$*")
                HASH=$(sha256sum "$*")
                HASH="${HASH#\\}" # removes leading backslash, see comment below
                printf '%s,%s\n' "${SIZE}" "${HASH/  /,}";;
            "124")
                >&2 printf 'Timeout: %s\n' "$*";;
            *)
                >&2 printf 'Error-code %s: %s\n' "$?" "$*";;
        esac
    }
    export -f makeHash

    eval "$fCommand" | parallel --will-cite -0 -N1 makeHash
    # If there is a backslash/line-break somewhere in the path,
    # sha256 will add a backslash to the start of the hash and
    # escape the other. This makes the file distinguishable from
    # those containing an already escaped backslash/line-break.
    # However, we want to consider two files equal even if one
    # lies in a path with backslash and tolerate the ambiguity.
)
