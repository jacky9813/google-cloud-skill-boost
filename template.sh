#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")

# Leave this variable blank if you want to enable doing all tasks at once
#DISABLE_ALL_TASK=1

splitter(){
    i=$(tput cols)
    while [ $i -gt "0" ]; do
    	echo -n =
        i=$(($i - 1))
    done
    echo ""
}
pause(){
    if [ -z "$GLOBAL_NON_STOP" ] || [ ! -z "$FORCE_PAUSE" ]; then
        read -p "Press Enter to continue"
    fi
}
check_return(){
    if [ $1 -ne "0" ]; then
        echo "Error detected"
        pause
    fi
}
echo_cmd(){
    splitter
	echo $@
	eval $@
    RET=$?
    if [ $RET -ne "0" ]; then
        echo "Error occured! You can ignore this message and press enter to continue."
        FORCE_PAUSE=1 pause
    fi
}
checkpoint(){
    splitter
    echo "Checkpoint reached"
    pause
}

# TODO: PUT THE TASKS HERE

run_all(){
if [ $DISABLE_ALL_TASK ] ; then
    echo "Doing all tasks at once has been disabled"
    exit 1
else
    if [ "$PROJECT" == "" ]; then
        echo "Warning: No selected project"
        echo "You can still proceed to execute anyway or press Ctrl-C to exit"
    else
        echo "Please confirm your target project is $PROJECT"
    fi
    pause
    task=${START_TASK:-$([ "$(echo $@ | wc -w)" -ge "2" ] && echo $2 || echo "1")}
    echo "Starting from task $task"
    echo ""
    echo "No argument will be able to passed to any task."
	echo "Are you sure you wanna do all at once?"
	pause
    while [[ $(type -t task$task) == function ]]; do
        splitter
    	task$task
    	task=$(($task + 1))
    done
fi
}

case "$1" in
    "all")
        run_all $@
        ;;
    "non-stop")
        GLOBAL_NON_STOP=1
        run_all $@
        ;;
    "help" | "")
        cat << EOF
Usage:
    $0 <task_number> <additional_args_for_task>
        Execute specified task.

    $0 all
        Execute all tasks from task 1.

    START_TASK=<task_number> $0 all
    - or -
    $0 all <task_number>
        Execute tasks start from specified task.

    $0 non-stop [task_number]
        Like "all" command but will not pause if executed as expected.

    $0 help
        Display this message
EOF
        ;;
    *)
        if [ "$PROJECT" == "" ]; then
        	echo "Warning: No selected project"
        	echo "You can still proceed to execute anyway or Ctrl-C to exit"
        else
        	echo "Please confirm your target project is $PROJECT"
        fi
        pause
        splitter
	    [[ $(type -t task$1) == function ]] && task$1 $@ || echo "No task named task$1"
        ;;
esac

