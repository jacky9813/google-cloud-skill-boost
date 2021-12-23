#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")

# Leave this variable blank if you want to enable doing all tasks at once
DISABLE_ALL_TASK=1

splitter(){
    i=$(tput cols)
    while [ $i -gt "0" ]; do
    	echo -n =
        i=$(($i - 1))
    done
}
pause(){
    read -p "Press Enter to continue"
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
        pause
    fi
}
checkpoint(){
    splitter
    echo "Checkpoint reached"
    pause
}

# TODO: PUT THE TASKS HERE
task1(){
cat << EOF
Task 1 - Viewing the available permissions for a resource
$(splitter)
The following command will output a VERY long listing of permissions that can be set for a role.
Feel free to interrupt the output using Ctrl-C.

This command will not write anything to the project.
EOF
pause
echo_cmd gcloud iam list-testable-permissions //cloudresourcemanager.googleapis.com/projects/$PROJECT
}

task2(){
ROLE_IN_QUESTION=roles/storage.objectViewer
cat << EOF
Task 2 - Getting the role matadata
$(splitter)
The following example output what permissions a role has (the "$ROLE_IN_QUESTION" role in this case)

This command will not write anything to the project.
EOF
pause
echo_cmd gcloud iam roles describe $ROLE_IN_QUESTION
}

task3(){
cat << EOF
Task 3 - Viewing the grantable roles on resources
$(splitter)
The following command outputs a listing of roles that can be assigned to a user/service account.

This command will not write anything to the project.
EOF
pause
echo_cmd gcloud iam list-grantable-roles //cloudresourcemanager.googleapis.com/projects/$PROJECT
}

task4(){
YAML_FILE=role-definition.yaml
cat << EOF
Task 4 - Create a custom role using YAML file
$(splitter)
This task uses YAML file to describe a role with proper permissions.
We'll be create a new role using a YAML file.

More info on: (Put a reference link here)

Here's the content of the "$YAML_FILE" YAML file

EOF
cat << EOF | tee $YAML_FILE
title: "Role Editor"
description: "Edit access for App Versions"
stage: "ALPHA"
includedPermissions:
- appengine.versions.create
- appengine.versions.delete
EOF
pause
echo_cmd gcloud iam roles create editor --project $PROJECT --file $YAML_FILE
checkpoint
}

task5(){
PERMISSIONS=compute.instances.get,compute.instances.list
DESC="Custom role description"
TITLE="Role Viewer"
cat << EOF
Task 5 - Create a custom role using flags
$(splitter)
Instead of using a YAML file, IAM role can also be described in one command.
EOF
pause
echo_cmd "gcloud iam roles create viewer --project $PROJECT --title '$TITLE' --description '$DESC' --permissions $PERMISSIONS --stage ALPHA"
checkpoint
}

task6(){
cat << EOF
Task 6 - Listing the custom roles
$(splitter)
We've created 2 custom roles so far.
This task will demonstrate how to list custom role of a project.
EOF
pause
echo_cmd gcloud iam roles list --project $PROJECT
splitter
cat << EOF
Additionally, adding the "--show-deleted" flag at the end can show deleted roles.
Since we've not deleted anything yet, we will not demonstrate here.
EOF
pause
splitter
cat << EOF
Using the command "gcloud iam roles list" can show all predefined roles.
Similar to the command used in task 3.
EOF
pause
}

task7(){
YAML_FILE=new-role-definition.yaml
ROLE=editor
cat << EOF
Task 7 - Updating a custom role using a YAML file
$(splitter)
We'll add 2 permissions to role $ROLE using YAML file.
The YAML file can be obtained using describe command.
EOF
pause
echo_cmd gcloud iam roles describe $ROLE --project $PROJECT | tee $YAML_FILE
splitter
cat << EOF
Added these permissions:
storage.buckets.get
storage.buckets.list
EOF
pause
EDITOR=${EDITOR:-vim}
echo_cmd $EDITOR $YAML_FILE
while [ "$(grep -E '\- storage.buckets.(get|list)' $YAML_FILE | wc -l)" -ne "2" ]; do
splitter
cat << EOF
Either storage.buckets.get or storage.buckets.list is missing.
Please try again.
EOF
pause
$EDITOR $YAML_FILE
done
echo_cmd gcloud iam roles update $ROLE --project $PROJECT --file $YAML_FILE
tail -n +2 $YAML_FILE | tee $YAML_FILE > /dev/null
checkpoint
}

task8(){
ROLE=viewer
ADD_PERMISSIONS=storage.buckets.get,storage.buckets.list
cat << EOF
Task 8 - Updating a custom role using command line flags
$(splitter)
We'll add 2 permissions to role $ROLE using command line only.
The newly added permissions are:
$(echo $ADD_PERMISSION | awk '{printf "%s\n%s\n", $1, $2}')
EOF
pause
echo_cmd gcloud iam roles update $ROLE --project $PROJECT --add-permissions $ADD_PERMISSIONS
checkpoint
}

task9(){
ROLE=viewer
cat << EOF
Task 9 - Disabling a role
$(splitter)
Change the stage of a role to DISABLED to disable a role.
In this task, we'll be disable the role $ROLE.
EOF
pause
echo_cmd gcloud iam roles update $ROLE --project $PROJECT --stage DISABLED
checkpoint
}

task10(){
ROLE=viewer
cat << EOF
Task 10 - Deleting a custom role
$(splitter)
This task will demonstrate how to delete a custom role, $ROLE in this case, from a project.
EOF
pause
echo_cmd gcloud iam roles delete $ROLE --project $PROJECT
splitter
cat << EOF
Once a role is deleted, deleted role will be set to "inactive" state or "DEPRECATED" stage.
Deleted role can be undeleted within 7 days.
After that, the role become permanent deleted for 30 days (day 7-37).
The role name will become available after day 37 of deletion.
EOF
pause
}

task11(){
ROLE=viewer
cat << EOF
Task 11 - Undelete a custom role
$(splitter)
This task will undo what task 10 has done.
EOF
pause
echo_cmd gcloud iam roles undelete $ROLE --project $PROJECT
checkpoint
}

case "$1" in
    "all")
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
    		echo "No argument will be able to passed to any task."
    		echo "Are you sure you wanna do all at once?"
    		pause
    		task=${START_TASK:-1}
    		while [[ $(type -t task$task) == function ]]; do
                splitter
    			task$task
    			task=$(($task + 1))
    		done
    	fi
        ;;
    "help" | "")
        cat << EOF
Usage:
    $0 <task_number>
        Execute specified task.

    $0 all
        Execute all tasks from task 1.

    START_TASK=<task_number> $0 all
        Execute tasks start from specified task.

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

