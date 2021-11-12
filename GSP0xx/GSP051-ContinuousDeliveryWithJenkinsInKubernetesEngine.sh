#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
CLUSTER_NAME=jenkins-cd
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
    local RET=$?
    if [ $RET -ne "0" ]; then
        echo "Error occured! You can ignore this message and press enter to continue."
        pause
    fi
    return $RET
}

task1(){
ORIGINAL_WD=$(realpath $(pwd))
cat << EOF
Task 1 - Preparation
This task covers the following sections in GSP051:
* Setup
* Clone the repository
* Provisioning Jenkins
* Setup Helm
* Configure and Install Jenkins
* Connect to Jenkins
EOF
pause

# Downloading repository and create a new k8s cluster
echo_cmd gcloud config set compute/zone us-east1-d
echo_cmd git clone https://github.com/GoogleCloudPlatform/continuous-deployment-on-kubernetes.git
echo_cmd cp $(realpath $0) continuous-deployment-on-kubernetes/
echo_cmd gcloud container clusters create $CLUSTER_NAME --num-nodes=2 --machine-type=n1-standard-2 --scopes="https://www.googleapis.com/auth/source.read_write,cloud-platform"
echo_cmd gcloud container clousters get-credentials $CLUSTER_NAME
echo_cmd kubectl cluster-info
splitter
echo "Checkpoint reached"
pause

# Install Jenkins to k8s cluster
echo_cmd helm repo add jenkins https://charts.jenkins.io
echo_cmd helm repo update
splitter
echo "** Warning: Changing directory to continuous-deployment-on-kubernetes"
cd continuous-deployment-on-kubernetes
echo_cmd gsutil cp gs://spls/gsp330/values.yaml jenkins/values.yaml
echo_cmd helm install cd jenkins/jenkins -f jenkins/values.yaml --wait
echo_cmd kubectl get pods
splitter
echo "Checkpoint reached"
pause

echo_cmd kubectl create clusterrolebinding jenkins-deploy --clusterrole=cluster-admin --serviceaccount=default:cd-jenkins

splitter
echo "Waiting Jenkins to be ready"
IP_ADDRESS=$(kubectl get services | grep LoadBalancer | grep jenkins | awk '{print $4}')
while [ "$IP_ADDRESS" == "<pending>" ]; do
sleep 1
IP_ADDRESS=$(kubectl get services | grep LoadBalancer | grep jenkins | awk '{print $4}')
done
sleep 10
echo_cmd kubectl get services

echo_cmd 'printf $(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo'
PASS=$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)
POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/component=jenkins-master" -l "app.kubernetes.io/instance=cd" -o jsonpath="{.items[0].metadata.name}")
splitter
cat << EOF
Connect to jenkins:
link: http://$IP_ADDRESS:8080
username: admin
password: $PASS

Or run "kubectl port-forward $POD_NAME 8080:8080" in another cloud console and click
"Web Preview" => "Preview on port 8080", then type in the same credential listed 
above.
But if you use this method, do not close that console before you've done all the
tasks.
EOF

splitter
echo "** Warning: Changing directory back"
cd $ORIGINAL_WD
} # End of task 1

task2(){
cat << EOF
Task 2 - Deploying the Application

We'll deploy the sample-app into a new namespace "production"
EOF
pause
splitter
ORIG_WD=$(pwd)
echo "Changing directory to sample-app"
cd sample-app
echo_cmd kubectl create ns production
if ! [ -d "k8s/production" ] || ! [ -d "k8s/canary" ] || ! [ -d "k8s/services" ]; then
cat << EOF
There're some files missing.
Check the existence of "production", "canary" and "services" directories inside "sample-app/k8s".

Switching back to original working directory.
EOF
cd $ORIG_WD
exit 1
fi
echo_cmd kubectl apply -f k8s/production -n production
echo_cmd kubectl apply -f k8s/canary -n production
echo_cmd kubectl apply -f k8s/services -n production
splitter
echo "Checkpoint reached"
pause

echo_cmd kubectl scale deployment gceme-frontend-production -n production --replicas 4
echo_cmd kubectl get pods -n production -l app=gceme -l role=frontend
echo_cmd kubectl get pods -n production -l app=gceme -l role=backend
splitter
echo "Waiting for LoadBalancer getting ready."
IP_ADDRESS = $(kubectl get -o jsonpath="{.status.loadBalancer.ingress[0].ip} --namespace=production services gceme-frontend")
while [ "$IP_ADDRESS" == "<pending>" ]; do
sleep 1
IP_ADDRESS = $(kubectl get -o jsonpath="{.status.loadBalancer.ingress[0].ip} --namespace=production services gceme-frontend")
done
sleep 10
echo_cmd kubectl get services -n production
echo_cmd curl http://$IP_ADDRESS/version
splitter
cat << EOF
The service is ready on IP $IP_ADDRESS
You can view info card by accessing http://$IP_ADDRESS through your browser
or check the application version using http://$IP_ADDRESS/version
EOF
pause
} # End of task 2

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

