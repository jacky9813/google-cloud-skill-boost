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
NEW_SA=my-sa-123
SA_DN="my service account"
cat << EOF
Before tasks begins, you should've understanded the concept of the Service Account.
Go to GSP199 course page if not or you wanna to review.
EOF
pause
cat << EOF
Task 1 - Creating a Service Account
$(splitter)
EOF
pause
echo_cmd "gcloud iam service-accounts create $NEW_SA --display-name '$SA_DN'"
}

task2(){
SA=my-sa-123
ROLE=roles/editor
cat << EOF
Task 2 - Granting roles to a service account
$(splitter)
EOF
pause
echo_cmd gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$SA@$PROJECT.iam.gserviceaccount.com --role $ROLE
checkpoint
}

task3(){
SA_NAME=bigquery-qwiklab
SA_ROLE=roles/bigquery.user,roles/bigquery.dataViewer
INST_NAME=bigquery-instance
INST_ZONE=us-central1-a
INST_MACHINE=n1-standard-1
INST_IMAGEFAMILY=debian-10
cat << EOF
Task 3 - Use the Client Libraries to Access BigQuery from a Service Account
$(splitter)
In this task, We'll be creating a service account with proper roles applied, creating a GCE instance and using a service account within the instance to access a resource (BigQuery in this case).
EOF
pause

echo_cmd gcloud iam service-accounts create $SA_NAME
echo_cmd gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$SA_NAME@$PROJECT.iam.gserviceaccount.com --role roles/bigquery.user
echo_cmd gcloud projects add-iam-policy-binding $PROJECT --member serviceAccount:$SA_NAME@$PROJECT.iam.gserviceaccount.com --role roles/bigquery.dataViewer

splitter
PROPAGATE_WAIT=60
echo "Waiting $PROPAGATE_WAIT secs for the roles to be propagated"
sleep $PROPAGATE_WAIT

echo_cmd gcloud compute instances create $INST_NAME --zone=$INST_ZONE --machine-type=$INST_MACHINE --service-account=$SA_NAME@$PROJECT.iam.gserviceaccount.com --scopes=bigquery

splitter
echo "Waiting for $INST_NAME getting ready"
gcloud compute instances list --filter="status:RUNNING AND name:$INST_NAME" 2>/dev/null | grep $INST_NAME > /dev/null
while [ "$?" -ne "0" ]; do
    sleep 5
    gcloud compute instances list --filter="status:RUNNING AND name:$INST_NAME" 2>/dev/null | grep $INST_NAME > /dev/null
done

splitter
cat << EOF
Inside the $INST_NAME, follow the instruction from the "Use the Client Libraries to Access BIgQuery from a Service Account" section in the course page.
EOF
pause

# The commands to prepare the environment
splitter
echo Commands
splitter
cat << EOF
sudo apt update && sudo apt install -y virtualenv
virtualenv -p python3 venv
source venv/bin/activate
sudo apt update && sudo apt install -y git python3-pip
pip install google-cloud-bigquery pyarrow pandas
EOF

# query.py
splitter
echo "query.py"
splitter
cat << EOF
from google.auth import compute_engine
from google.cloud import bigquery
credentials = compute_engine.Credentials(
    service_account_email='$SA_NAME@$PROJECT.iam.gserviceaccount.com')
query = '''
SELECT
  year,
  COUNT(1) as num_babies
FROM
  publicdata.samples.natality
WHERE
  year > 2000
GROUP BY
  year
'''
client = bigquery.Client(
    project='$PROJECT',
    credentials=credentials)
print(client.query(query).to_dataframe())
EOF

echo "Connecting to $INST_NAME..."
echo_cmd gcloud compute ssh $INST_NAME --zone=$INST_ZONE
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

