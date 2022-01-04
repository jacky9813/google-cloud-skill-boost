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
REGION=us-central1
ZONE=$REGION-a
NEW_DB_INST_NAME=blog-mysql80

# Here's a list of supported database version descriptor:
# https://cloud.google.com/sql/docs/mysql/admin-api/rest/v1beta4/SqlDatabaseVersion
NEW_DB_VERSION=MYSQL_8_0
NEW_DB_ROOT_PW=$(cat .newdb-root-passwd 2>/dev/null)
NEW_DB_ROOT_PW=${NEW_DB_ROOT_PW:-$(dd if=/dev/urandom bs=12 count=1 2>/dev/null | base64)}
echo $NEW_DB_ROOT_PW > .newdb-root-passwd
NEW_DB_CORE=2
NEW_DB_MEM=8GiB # Default unit is GiB
NEW_DB_NS=wordpress
# The monitor instance need access too. (Come on Qwiklabs, you should tell us at the very beginning.)
NEW_DB_AUTH_NETWORK=
for addr in $(gcloud compute instances list --format="csv[no-heading](EXTERNAL_IP)"); do
    if [ -z $NEW_DB_AUTH_NETWORK ]; then
        NEW_DB_AUTH_NETWORK=$addr
    else
        NEW_DB_AUTH_NETWORK=$NEW_DB_AUTH_NETWORK,$addr
    fi
done

DB_USER=blogadmin
DB_USER_PW="Password1*"

BUCKET_NAME=$(cat .gcs-bucket 2>/dev/null)
BUCKET_NAME=${BUCKET_NAME:-gsp306-$(dd if=/dev/urandom bs=12 count=1 2>/dev/null | base64 | sed -E "s/[\/=\+]//g" | awk '{print tolower($0)}')}
echo $BUCKET_NAME > .gcs-bucket
SQL_DUMP_URI=gs://$BUCKET_NAME/dump.sql.gz

task1(){
cat << EOF
Task 1 - Prepare a new Cloud SQL instance
$(splitter)
In this task, we'll:
* Create a new database instance
* Create a database
* Create a user using old credentials

=========================
Note: The authorized network checkpoint cannot work for some reason.
I've sent out a support ticket asking about it at Jan 4, 2022 12:08 (+0800 Taipei Time).
=========================
EOF
pause

# Don't know why but I cannot create an instance at the same subnet as the blog.
# All I can do is to create an instance using public facing address with restriction.
echo_cmd gcloud sql instances create $NEW_DB_INST_NAME \
    --database-version=$NEW_DB_VERSION \
    --database-flags=character_set_server=utf8mb4 \
    --zone=$ZONE \
    --cpu=$NEW_DB_CORE --memory=$NEW_DB_MEM \
    --root-password=$NEW_DB_ROOT_PW \
    --authorized-networks=$NEW_DB_AUTH_NETWORK
splitter
cat << EOF
Here's the newly created database's root password:
$NEW_DB_ROOT_PW
EOF

echo_cmd gcloud sql databases create wordpress --instance=$NEW_DB_INST_NAME
echo_cmd gcloud sql users create $DB_USER --instance=$NEW_DB_INST_NAME --password=$DB_USER_PW --type=BUILT_IN
} # End of task 1

task2(){
cat << EOF
Task 2 - Moving data
$(splitter)
In this task, we'll:
* Dump the data to a bucket
* Import the data into Cloud SQL
EOF
pause
echo_cmd gsutil mb gs://$BUCKET_NAME
# For generating SSH key and add to known hosts
gcloud compute ssh blog --zone=$ZONE --command="exit 0"

splitter
echo "gcloud compute ssh blog --zone=$ZONE --command=\"mysqldump --user=$DB_USER --password=$DB_USER_PW wordpress\" | gzip -c | gsutil cp - $SQL_DUMP_URI"

# Don't know if the instance have write permission. Upload from here instead.
gcloud compute ssh blog --zone=$ZONE --command="mysqldump --user=$DB_USER --password=$DB_USER_PW wordpress" | gzip -c | gsutil cp - $SQL_DUMP_URI

echo "Granting access to the bucket"
SQL_SVC_ACCOUNT=$(gcloud sql instances describe $NEW_DB_INST_NAME --format=json | jq -r ".serviceAccountEmailAddress")
echo_cmd gsutil acl ch -u $SQL_SVC_ACCOUNT:R $SQL_DUMP_URI

echo_cmd gcloud sql import sql $NEW_DB_INST_NAME $SQL_DUMP_URI --database=wordpress
} # End of task 2

task3(){
cat << EOF
Task 3 - Modifying the connection
$(splitter)
EOF
pause
splitter
echo "Generating the script for updating database configuration..."
NEW_DB_ADDR=$(gcloud sql instances list --filter="name:$NEW_DB_INST_NAME" --limit=1 --format="csv[no-heading](PRIMARY_ADDRESS)")
CONFIG_FILE=/var/www/html/wordpress/wp-config.php
cat << EOF | gsutil cp - gs://$BUCKET_NAME/update-sql-host.sh
#!/bin/bash
if [ ! -f $CONFIG_FILE.old ]; then
    echo "Making backup for wp-config.php"
    sudo cp $CONFIG_FILE $CONFIG_FILE.old
fi
echo "Patching..."
cat $CONFIG_FILE.old | sed -E "s/['\"]DB_HOST['\"] *, *['\"][^'\"]*['\"]/'DB_HOST', '$NEW_DB_ADDR'/g" | sudo tee $CONFIG_FILE > /dev/null
# MariaDB is symlinked to mysql as well, stopping mysql
echo "Stopping MySQL service"
sudo systemctl stop mysql
echo "Restarting Apache HTTP Server"
sudo systemctl restart apache2
EOF

# Hopefully the instance have read permission.
echo_cmd "gcloud compute ssh blog --zone=$ZONE --command='gsutil cat gs://$BUCKET_NAME/update-sql-host.sh | bash -'"
} # End of task 3


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

