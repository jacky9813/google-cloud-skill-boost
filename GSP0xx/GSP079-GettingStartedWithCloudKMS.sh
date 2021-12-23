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
KEYRING_NAME=test
CRYPTOKEY_NAME=qwiklab

task1(){
cat << EOF
Task 1 - Create a Google Cloud Storage (GCS) bucket
$(splitter)
EOF
pause
BUCKET_NAME=$(dd if=/dev/urandom bs=12 count=1 | base64 | sed "s/[\/\+]//g" | awk '{print tolower($0)}')_enron_corpus
echo $BUCKET_NAME > .bucket_name
echo "Creating a new bucket called $BUCKET_NAME"
echo_cmd gsutil mb gs://$BUCKET_NAME
checkpoint
}

task2(){
cat << EOF
Task 2 - Enable Cloud KMS
$(splitter)
EOF
pause
echo_cmd gcloud services enable cloudkms.googleapis.com
}

task3(){
cat << EOF
Task 3 - Create keyring and encryption key
$(splitter)
EOF
pause
echo_cmd gcloud kms keyrings create $KEYRING_NAME --location global
echo_cmd gcloud kms keys create $CRYPTOKEY_NAME --location global --keyring $KEYRING_NAME --purpose encryption
checkpoint
}

task4(){
BUCKET_NAME=${BUCKET_NAME:-$(cat .bucket_name)}
cat << EOF
Task 4 - Encrypt data
$(splitter)
EOF
pause
echo "Fetching sample data"
echo_cmd gsutil cp gs://enron_emails/allen-p/inbox/1. .
splitter
echo 'PLAINTEXT=$(cat 1. | base64 -w0)'
PLAINTEXT=$(cat 1. | base64 -w0)

splitter
echo 'curl -v "https://cloudkms.googleapis.com/v1/projects/$PROJECT/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:encrypt" -d "{\"plaintext\":\"$PLAINTEXT\"}" -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" -H "Content-Type: application/json" | jq .ciphertext -r > 1.encrypted'
curl -v "https://cloudkms.googleapis.com/v1/projects/$PROJECT/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:encrypt" -d "{\"plaintext\":\"$PLAINTEXT\"}" -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" -H "Content-Type: application/json" | jq .ciphertext -r > 1.encrypted

splitter
echo 'curl -v "https://cloudkms.googleapis.com/v1/projects/$PROJECT/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:decrypt" -d "{\"ciphertext\":\"$(cat 1.encrypted)\"}" -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" -H "Content-Type: application/json" | jq .plaintext -r | base64 -d'
curl -v "https://cloudkms.googleapis.com/v1/projects/$PROJECT/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:decrypt" -d "{\"ciphertext\":\"$(cat 1.encrypted)\"}" -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" -H "Content-Type: application/json" | jq .plaintext -r | base64 -d

echo_cmd gsutil cp 1.encrypted gs://$BUCKET_NAME
}

task5(){
USER_EMAIL=$(gcloud auth list --format="csv(account)" --limit=1 | tail -n +2)
cat << EOF
Task 5 - Configure IAM permission
$(splitter)
In this task, we'll add two permissions for user $USER_EMAIL:
- roles/cloudkms.admin
- roles/cloudkms.cryptoKeyEncrypterDecrypter

For what these role can do, use command "gcloud iam roles describe [role_name]"
EOF
pause
echo_cmd gcloud kms keyrings add-iam-policy-binding $KEYRING_NAME --location global --member=user:$USER_EMAIL --role=roles/cloudkms.admin
echo_cmd gcloud kms keyrings add-iam-policy-binding $KEYRING_NAME --location global --member=user:$USER_EMAIL --role=roles/cloudkms.cryptoKeyEncrypterDecrypter
}

task6(){
BUCKET_NAME=${BUCKET_NAME:-$(cat .bucket_name)}
cat << EOF
Task 6 - Encrypt data and upload to Google Cloud Storage (GCS)
$(splitter)
EOF
pause
splitter
echo "Downloading sample files"
echo_cmd gsutil -m cp -r gs://enron_emails/allen-p .

splitter
echo "Encrypting all data"
MYDIR=allen-p
FILES=$(find $MYDIR -type f -not -name "*.encrypted")
for file in $FILES; do
    PLAINTEXT=$(cat $file | base64 -w0)
    curl -v "https://cloudkms.googleapis.com/v1/projects/$PROJECT/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:encrypt" -d "{\"plaintext\":\"$PLAINTEXT\"}" -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" -H "Content-Type: application/json" | jq .ciphertext -r > $file.encrypted
    echo "$file >> $file.encrypted"
done

splitter
echo "Upload encrypted files"
echo_cmd gsutil -m cp $MYDIR/inbox/*.encrypted gs://$BUCKET_NAME/allen-p/inbox
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

