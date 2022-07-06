#!/bin/bash

# Simple mysqld start script for containers
# We do not use mysqld_safe

# Variables

MYSQLD=mysqld
LOG_MESSAGE="Docker startscript:"
wsrep_recover_position=
OPT="$@"

# Do we want to check for programs?

which $MYSQLD || exit 1

# Check for mysql.* schema
# If it does not exist we got to create it

test -d /var/lib/mysql/mysql
if [ $? != 0 ]; then
  mysql_install_db --user=mysql
  if [ $? != 0 ]; then
    echo "${LOG_MESSAGE} Tried to install mysql.* schema because /var/lib/mysql/mysql is not a directory"
    echo "${LOG_MESSAGE} it failed :("
  fi
fi

# Get the GTID possition

echo  "${LOG_MESSAGE} Get the GTID positon"
tmpfile=$(mktemp)
$MYSQLD --wsrep-recover 2>${tmpfile}
if [ $? != 0 ]; then
  echo "${LOG_MESSAGE} An error happened while trying to '--wsrep-recover'"
  cat ${tmpfile}
  rm  ${tmpfile}
  exit 1
fi

wsrep_start_position=$(sed -n 's/.*Recovered\ position:\s*//p' ${tmpfile})

# What should we do if there is no recoverd position?
# We will not start, as most likely Galera is not configured

if test -z ${wsrep_start_position}
  then echo "${LOG_MESSAGE} We found no wsrep position!"
       echo "${LOG_MESSAGE} Most likely Galera is not configured, so we refuse to start"
       exit 1
fi

# Start mysqld


# Start Consul


CONSULEXIT=
trap '$CONSULEXIT; kill -TERM $PID' TERM INT
if [ -z "$CONSULDATA" ]; then export CONSULDATA="/tmp/consul-data";fi
if [ -z "$CONSULDIR" ]; then export CONSULDIR="/consul";fi
if [[ "$(ls -A $CONSULDIR)" ]] || [[ -n $CONSULOPTS  ]]; then
    CONSULEXIT="consul leave"
    consul agent -data-dir=$CONSULDATA -config-dir=$CONSULDIR $CONSULOPTS &
    CONSULPID=$!
elif [[ -n "$CONSULHTTP" ]] && [[ -n "$SERVICEFILE" ]];then
    # This option allow to use a pre-existing consul agent to register the service
    echo "Registering Galera to Consul at ${CONSULHTTP} using file: $SERVICEFILE"
    # This don't work, see next line for alternative method
    #consul services register -http-addr=$CONSULHTTP $SERVICEFILE 
    curl -X PUT --data @$SERVICEFILE $CONSULHTTP/v1/agent/service/register
    service_id=$(jq -r '.name' $SERVICEFILE)
    CONSULEXIT="curl -X PUT $CONSULHTTP/v1/agent/service/deregister/$service_id"
fi

if [[ -n $DATABASE_HOST ]] && [[ -n $CONSULEXIT ]]; then
    echo "${LOG_MESSAGE} Looking for other peers under same host."
    MYIP="`hostname -I | xargs`"
    CLUSTER_IPS=
    for ip in `dig ${DATABASE_HOST} +short`; do
    if [ "$ip" != "$MYIP" ]; then
      CLUSTER_IPS="${CLUSTER_IPS}${CLUSTER_IPS:+,}$ip"
    fi
    done
    OPT="$OPT --wsrep-cluster-address=gcomm://$CLUSTER_IPS"
fi

# Start mysqld
OPT="$OPT --wsrep_start_position=$wsrep_start_position"
echo "${LOG_MESSAGE} Starting mysqld daemon with args: $OPT"
$MYSQLD $OPT &\
PID=$!  

if [[ -n $DATABASE_DB ]] && [[ -n $DATABASE_USER ]]  && [[ -n $DATABASE_PASS ]]; then
  sleep 20
  echo "${LOG_MESSAGE} Creating default database '${DATABASE_DB}' for user '${DATABASE_USER}'.."
  mysqladmin create $DATABASE_DB &&\
  mysql -u root -e "GRANT ALL PRIVILEGES ON $DATABASE_DB.* TO '$DATABASE_USER'@'%' IDENTIFIED BY '$DATABASE_PASS';"
fi

wait $CONSULPID 
wait $PID
trap - TERM INT
wait $PID
