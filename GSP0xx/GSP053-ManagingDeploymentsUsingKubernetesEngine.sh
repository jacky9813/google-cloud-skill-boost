#!/bin/bash
# GSP053 - Managing Deployments Using Kubernetes Engine
#
# This course should be taken after GSP021 or other basic kubernetes deployment courses.
#

PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
CLUSTER_NAME=bootcamp

# Leave this variable blank if you want to enable doing all tasks at once
DISABLE_ALL_TASK=

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
	echo ================================================================================
	echo $@
	eval $@
    RET=$?
    if [ $? -ne "0" ]; then
        echo "Error occured"
        pause
    fi
    return $RET
}

task1(){
cat << EOF
Task 1 - Preparation
EOF
# Setting up default zone
echo_cmd gcloud config set compute/zone us-central1-a

# Retrieving sample code
echo_cmd gsutil -m cp -r gs://spls/gsp053/orchestrate-with-kubernetes .

# Create 5 node cluster
echo_cmd gcloud container clusters create $CLUSTER_NAME \
    --num-nodes=5 \
    --scopes="https://www.googleapis.com/auth/projecthosting,storage-rw"

# Setup kubernetes credentials
echo_cmd gcloud container clusters get-credentials $CLUSTER_NAME

# Copy this script
echo_cmd cp $(realpath $0) orchestrate-with-kubernetes/kubernetes/

cat << EOF
================================================================================
  Please switch to orchestrate-with-kubernetes/kubernetes to continue.
  This script file has been copied to there.
================================================================================
EOF
} # End of task 1

task2(){
AUTH_DEPLOY_YAML=deployments/auth.yaml
cat << EOF
Task 2 - Create a deployment

Prior to do the tasks, you should have basic understanding of what deployment and
its metadata are.
You can use commands below if you wanna to learn more:
"kubectl explain deployment"
"kubectl explain deployment --resursive"
"kubectl explain deployment.metadata.name"

In this task, we'll create several deployments and services for future tasks.
But before that, you need to change the auth container's image to
"kelseyhightower/auth:1.0.0".

(If you have a preferred text editor, set it up at EDITOR variable in yout shell.)
EOF
pause
if [ "$EDITOR" == "" ]; then
# Defaults to VIM
vim $AUTH_DEPLOY_YAML
else
# Use user preferred editor
$EDITOR $AUTH_DEPLOY_YAML
fi
cat $AUTH_DEPLOY_YAML | grep "kelseyhightower/auth:1.0.0" > /dev/null
echo_cmd cat $AUTH_DEPLOY_YAML
if ! [ -z "$?" ]; then
    echo "Check the configuration file $AUTH_DEPLOY_YAML again."
    exit 1
fi

# Creating pod(s)
echo_cmd kubectl create -f $AUTH_DEPLOY_YAML

# Series of deployment status checks.
echo_cmd kubectl get deployments
echo "Verify if the deployment has successed."
pause

echo_cmd kubectl get replicasets
echo "Verify the Replica Sets has been created."
pause

echo_cmd kubectl get pods
echo "Verify the pods has been created."
pause

# Create remaining deployments
echo_cmd kubectl create -f services/auth.yaml
echo_cmd kubectl create -f deployments/hello.yaml
echo_cmd kubectl create -f services/hello.yaml
echo_cmd kubectl create secret generic tls-certs --from-file tls/
echo_cmd kubectl create configmap nginx-frontend-conf --from-file=nginx/frontend.conf
echo_cmd kubectl create -f deployments/frontend.yaml
echo_cmd kubectl create -f services/frontend.yaml

cat << EOF
================================================================================
Load balancer is getting ready...
EOF
IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print $4}')
while [ $IP_ADDRESS == "<pending>" ]; do
    sleep 1
    IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print $4}')
done
sleep 10
echo_cmd kubectl get services frontend

echo "Using IP address $IP_ADDRESS"
echo_cmd curl -ks https://$IP_ADDRESS

echo "Checkpoint reached"
pause
} # End of task 2

task3(){
cat << EOF
Task 3 - Scale a Deployment
This task focuses on rescaling a deployment by modifying the 'spec.replicas' field.
The command 'kubectl explain deployment.spec.replicas' to have more detailed explaination.
EOF
pause
echo_cmd kubectl explain deployment.spec.replicas

echo "Changing the hello deployment to 5 replicas"
echo_cmd kubectl scale deployment hello --replicas=5

echo "Waiting for all 5 pods get online"
POD_COUNT=$(kubectl get pods | grep hello- | wc -l)
while [ $POD_COUNT -lt 5 ]; do
    sleep 1
    POD_COUNT=$(kubectl get pods | grep hello- | wc -l)
done
echo_cmd "kubectl get pods | grep hello-"

cat << EOF
================================================================================
Now you shall see there're 5 pods for hello deployment.

We'll scale back down to 3 pods now.
EOF
pause
echo_cmd kubectl scale deployment hello --replicas=3
echo "Waiting for hello deployment scale back to 3 pods..."
while [ $POD_COUNT -gt 3 ]; do
    sleep 1
    POD_COUNT=$(kubectl get pods | grep hello- | wc -l)
done
echo_cmd "kubectl get pods | grep hello-"
} # End of task 3

task4(){
cat << EOF
Task 4 - Rolling update
By editing the deployment file using "kubectl edit deployment <deployment name>",
kubernetes will slowly apply the changes (creating new pod and closes unmatched ones).

The following command will open an editor.
Edit the container image to "kelseyhightower/hello:2.0.0" for version upgrading.
EOF
pause
echo_cmd kubectl edit deployment hello
cat << EOF
================================================================================
From now on, assuming you entered correct settings, kubernetes will start the update.

You can use command "kubectl get replicaset" to see the new ReplicaSet kubernetes has
created.
And "kubectl rollout history deployment/hello" for checking rollout history.
We'll execute both command after you've pressed the Enter key.
EOF
pause
echo_cmd kubectl get replicaset
echo_cmd kubectl rollout history deployment/hello

cat << EOF
================================================================================
If you've observed any issue during the rollout process, you can pause the rollout
with "kubectl rollout pause deployment/<deployment name>"

We'll demonstrate how to pause the hello deployment process and verify rollout has
been paused.
EOF
pause
echo_cmd kubectl rollout pause deployment/hello
echo_cmd kubectl rollout status deployment/hello
echo_cmd kubectl get pods -o jsonpath --template='{range .items[*]}{.metadata.name}{"\t"}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

cat << EOF
================================================================================
When there's pause, there will be a resume process.
And just replacing "pause" with "resume" will work, which forms the command:
"kubectl rollout resume deployment/<deployment name>"

We'll resume and verify the rollout process for hello deployment next.
EOF
pause
echo_cmd kubectl rollout resume deployment/hello
echo_cmd kubectl rollout status deployment/hello

cat <<EOF
================================================================================
But when new version has been discovered causing problem to your service, you can
rollback to previous version with a simple command:
"kubectl rollout undo deployment/<deployment name>"

We'll demonstrate and verify rollback process on hello deployment next.
EOF
pause
echo_cmd kubectl rollout undo deployment/hello
echo_cmd kubectl rollout history deployment/hello
echo_cmd kubectl get pods -o jsonpath --template='{range .items[*]}{.metadata.name}{"\t"}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
} # End of task 4


_task5_catch_sigint(){
    if [ -z $_TASK5_IN_LOOP ]; then
        exit 1
    else
        _TASK5_EXIT_LOOP=1
    fi
}

task5(){
HELLO_CANARY_DPLY_YML=deployments/hello-canary.yaml
cat << EOF
Task 5 - Canary deployments
To prevent potential catastrophe caused by new version of the software, doing some
testing in testing environment is important.

In this task, we'll demostrate how to deploy containers to different "track" than
your typical production deployment.
We'll be using $HELLO_CANARY_DPLY_YML to deploy testing services.
EOF
pause
echo_cmd cat $HELLO_CANARY_DPLY_YML
echo_cmd kubectl create -f $HELLO_CANARY_DPLY_YML
echo_cmd kubectl get deployments

cat <<EOF
================================================================================
Now you should notice there's a new deployment called hello-canary.
The service will pick it up as one of its worker pod.
Since there's only one canary pods within 4 hello pods, requests being served by
hello/2.0.0 is about 25%

We'll test it out now.
EOF
pause
echo "Checking IP address..."
IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print $4}')
while [ $IP_ADDRESS == "<pending>" ]; do
    sleep 1
    IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print $4}')
done
sleep 10
echo_cmd kubectl get services frontend

echo "(Press Ctrl-C to stop testing)"

_TASK5_EXIT_LOOP=0
_TASK5_IN_LOOP=1
trap _task5_catch_sigint SIGINT
while [ $_TASK5_EXIT_LOOP -ne 0 ]; do
echo_cmd curl -ks https://$IP_ADDRESS/version
sleep 1
done
trap - SIGINT #Clear the trap

echo "Checkpoint reached"
pause

cat << EOF
Instead of having those 25% (in our example) to be served, we can specify who uses
canary pods by editing "spec.sessionAffinity" to the client IP address.

Due to the difficulty of set up the environment in this course, we'll not
demonstrate here, but it is very important when deploying out in the field.
EOF
pause
} # End of task 5

if [ "$PROJECT" == "" ]; then
	echo "Warning: No selected project"
	echo "You can still proceed to execute anyway or Ctrl-C to exit"
else
	echo "Please confirm your target project is $PROJECT"
fi
pause
if [ "$1" == "all" ]; then
	if [ $DISABLE_ALL_TASK ] ; then
		echo "Doing all tasks at once has been disabled"
		exit 1
	else
		echo "No argument will be able to passed to any task."
		echo "Are you sure you wanna do all at once?"
		pause
		task=1
		while [[ $(type -t task$task) == function ]]; do
			task$task
			task=$(($task + 1))
		done
	fi
else
	[[ $(type -t task$1) == function ]] && task$1 $@ && echo "Task $1 Completed" || echo "No task named task$1"
fi

