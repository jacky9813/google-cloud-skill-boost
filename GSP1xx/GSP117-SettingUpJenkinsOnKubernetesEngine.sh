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
    echo ""
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
	$@
}

task1(){
cat << EOF
Task 1 - Preparation
EOF
pause
echo_cmd gcloud config set compute/zone us-east1-d
echo_cmd git clone https://github.com/GoogleCloudPlatform/continuous-deployment-on-kubernetes.git
echo_cmd cp $(realpath $0) continuous-deployment-on-kubernetes/
echo_cmd 'gcloud container clusters create jenkins-cd --num-nodes=2 --machine-type=n1-standard-2 --scopes="https://www.googleapis.com/auth/projecthosting,https://www.googleapis.com/auth/cloud-platform"'
echo_cmd gcloud container clusters get-credentials jenkins-cd
echo_cmd kubectl cluster-info
echo_cmd helm repo add stable https://charts.helm.sh/stable
echo_cmd helm repo update
splitter
cat << EOF
  Navigate to "continuous-deployment-on-kubernetes" and continue the tasks.
  This script has been copied to there.
  
  If you want to do all tasks at once, use command "START_TASK=2 $0 all".
EOF
splitter
echo "Checkpoint reached"
pause
}

task2(){
JENKINS_VAL_YML=jenkins/values.yaml
if ! [ -f "$JENKINS_VAL_YML" ]; then
echo "Error: The file \"$JENKINS_VAL_YML\" not found"
exit 1
fi
cat << EOF
Task 2 - Configure and Install Jenkins using Helm
EOF
pause
echo_cmd helm install cd stable/jenkins -f $JENKINS_VAL_YML --version 1.2.2 --wait
splitter
echo "Checkpoint reached"
pause
echo_cmd kubectl get pods
echo_cmd kubectl get services
PASS = $(printf $(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode); echo)
echo_cmd 'printf $(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode) ;echo'
splitter
cat << EOF
To access the Jenkins user interface, click "Web Preview" on the cloud console, then click "Preview on port 8080"

Use these credential to login.
username: admin
password: $PASS
EOF
splitter
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

