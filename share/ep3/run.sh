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
    (cd $dir && run.rb 'sh job.sh')
done

notifyquit="echo stop > $target_dir/ep3/control"

echo $target_dir/status/ExecutionState | entr -prsn "$notifyquit; kill -INT -- $PID"&
entrpid=$!

trap "$notifyquit; kill -INT -- $entrpid" 2 15

echo prepared

wait
