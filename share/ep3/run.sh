#!/bin/sh

target_dir=$(cd $(dirname $0) && pwd -P)
PATH=$EP3_LIBPATH/runtime:$PATH
EP3_ID=ep3.system.runner
SHELL=/bin/sh
PID=$$

for f in $target_dir/ep3/control $target_dir/status/ExecutionState
do
    if [ ! -f $f ]; then
        touch $f
    fi
done

for job in $(find $target_dir -name job.sh)
do
    dir=$(dirname $job)
    (cd $dir && sh job.sh)&
done

notifyquit="transition -o $target_dir/ep3/control=stop"

printf "$target_dir/status/ExecutionState\n" | entr -prsn "$notifyquit; kill -s USR1 $PID"&
entrpid=$!

trap "$notifyquit; kill -s USR1 $PID" INT
trap "kill -s INT $entrpid" USR1

wait
