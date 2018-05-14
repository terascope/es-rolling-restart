#!/bin/bash

# Parameters
#   -m - MASTER - The master node to use for coordinating the update.
#   -n - NODE_FILE - A file containing the list of node hostnames one per line.
#   -s SCRIPT - Script to run on each node to process the update. Script will have access to $MASTER and $NODE
#   -d SHUTDOWN_SCRIPT - Script to run to stop elasticsearch node.

while getopts ":d:m:n:s:h" opt; do
    case $opt in
        d)
            SHUTDOWN_SCRIPT=${OPTARG}
            echo "Shutdown script $SHUTDOWN_SCRIPT will be run for each node" >&2
            ;;
        m)
            export MASTER=${OPTARG}
            echo "Using master node: $MASTER" >&2
            ;;
        n)
            NODE_FILE=${OPTARG}
            echo "Reading list of node names from $NODE_FILE" >&2
            ;;
        s)
            SCRIPT=$OPTARG
            echo "Script $SCRIPT will be run for each node" >&2
            ;;
        h)
            echo "Usage: $0 [-h] [-m master node host name] [-d node name domains] [-p node port] [-n file containing list of nodes] [-s update script]"
            exit 1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit -1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit -1
            ;;
    esac
done

if [ -z $MASTER ]; then
    echo "Master node name including port must be provided. ex: -m localhost:9200"
    exit -1
fi

if [ -z $NODE_FILE ]; then
    echo "Path to a file containing the list of nodes must be provided. ex: -n /path/to/nodes_names.txt"
    exit -1
fi

if [ -z $SCRIPT ]; then
    echo "Path to the update script must be provided. ex: /path/to/update_script.sh"
    exit -1
fi

if [ -z $SHUTDOWN_SCRIPT ]; then
    echo "Path to the shutdown script must be provided ex: -d /path/to/shutdown_script.sh"
    exit -1
fi

# Test for existance of required files.
for file in $NODE_FILE $SCRIPT $SHUTDOWN_SCRIPT
do
    if [ ! -f $file ]; then
        echo "File not found: $file"
        exit -1
    fi
done

# Test that files to be called with eval in in the path or have full or
# relative paths specified
for file in $SCRIPT $SHUTDOWN_SCRIPT
do
    path_to_file=$(which ${file})
    if [ "$path_to_file" == "" ]; then
        echo "File not found: $file"
	echo "Perhaps you need to prepend ./ to the filename."
        exit -1
    fi
done

# Read the list of nodes into an array.
IFS=$'\r\n' GLOBIGNORE='*' :; NODES=($(< $NODE_FILE))

# Loop through the list
for NODE in ${NODES[@]}; do
    export NODE
    export HOST=${NODE%%:*}  # keep everything before the ':', hostname
    export PORT=${NODE##*:}  # keep everything after the ':', port number

    echo ">>>>>> Restarting ${NODE} at $(date)"

    STATUS=""
    echo ">>>>>> Verifying green cluster status"
    while [ -z "$STATUS" ];
    do
        # verify cluster is green
        STATUS=`curl -sS -XGET $MASTER/_cat/health | cut -f 4 -d ' ' | grep green`
        sleep 1
    done

    # if green, disable routing allocation for everything except newly
    # created primary shards

    echo ">>>>>> Disabling routing allocation"
    STATUS=`curl -XPUT -sS $MASTER/_cluster/settings -d '{ "transient" : { "cluster.routing.allocation.enable" : "new_primaries" } }'`

    if ! [[ "$STATUS" =~ (\"acknowledged\":true) ]] ; then
        echo "Failed acknowledge of allocation disable for ${NODE}"
        continue
    fi

    # Run the specified SHUTDOWN_SCRIPT to request shutdown of NODE.

    echo ">>>>>> Running shutdown script for ${NODE}"

    eval $SHUTDOWN_SCRIPT
    result=$?
    if [ $result != 0 ]; then
        printf ">>>>>> Error: [%d] when executing command: '$SHUTDOWN_SCRIPT' for node $NODE" $result
	exit -1
    fi

    # wait for the node to stop
    echo ">>>>>> Waiting for node to stop."
    STATUS=`curl -sS -XGET http://${NODE}/`
    while [[ "$STATUS" =~ (\"status\" : 200) ]];
    do
        STATUS=`curl -sS -XGET http://${NODE}/`

        sleep 1
    done

    echo ">>>>>> Waiting for cluster to reach yellow status"
    # wait for cluster status yellow
    STATUS=""
    while [ -z "$STATUS" ];
    do
        STATUS=`curl -sS -XGET $MASTER/_cat/health | cut -f 4 -d ' ' | grep yellow`
        sleep 1
    done

    # Perform changes to the node
    echo ">>>>>> Running updates on ${NODE}"

    eval $SCRIPT
    result=$?
    if [ $result != 0 ]; then
        printf ">>>>>> Error: [%d] when executing command: '$SCRIPT' on node $NODE" $result
    fi

    echo ">>>>>> Waiting for node ${NODE} to respond after restart. Connection refused messages expected."
    # verify node respond
    STATUS=""
    while ! [[ "$STATUS" =~ (\"tagline\" : \"You Know, for Search\") ]];
    do
        echo "fetching http://${NODE}/"
        STATUS=`curl -sS -XGET http://${NODE}/`
        sleep 1
    done

    echo ">>>>>> Verify restarted node sees cluster as yellow"
    # wait for cluster status yellow by talking directly to the restarted node.
    STATUS=""
    while [ -z "$STATUS" ];
    do
        STATUS=`curl -sS -XGET http://${NODE}/_cat/health | cut -f 4 -d ' ' | grep yellow`
        sleep 1
    done

    # We've had problems on larger clusters with nodes behaving as if routing
    # was re-enabled before the node was fully joined to the cluster (e.g.
    # the shards were vacated from the node when the should not have been)
    # This has led us to believe that the check for cluster yellow on the node
    # is not truly sufficient to ensure the shards won't be reallocated.
    # in ES 2.X and 5.X we have been unable to find an API endpoint that will
    # provide us with a better indication of node availability, so we sleep
    # longer.
    sleep 60

    echo ">>>>>> Re-enabling routing allocation"
    # re-enable routing allocation
    STATUS=`curl -sS -XPUT ${MASTER}/_cluster/settings -d '{ "transient" : { "cluster.routing.allocation.enable" : "all" } }'`

    if ! [[ "$STATUS" =~ (\"acknowledged\":true) ]] ; then
        echo "Failed acknowledge of allocation enable for ${NODE}. Will try again."
    fi

    sleep 15

    echo ">>>>>> Re-enabling routing allocation one more time"
    # re-enable routing allocation
    STATUS=`curl -sS -XPUT ${MASTER}/_cluster/settings -d '{ "transient" : { "cluster.routing.allocation.enable" : "all" } }'`

    if ! [[ "$STATUS" =~ (\"acknowledged\":true) ]] ; then
        echo "Failed acknowledge of allocation enable for ${NODE}. Continuing but manual intervention may be required."
    fi

    echo ">>>>>> Waiting for green cluster status"
    # wait for cluster status green by talking directly to the restarted node.
    STATUS=""
    COUNT=0
    ITERATIONS=0
    while [ -z "$STATUS" ];
    do
        # verify cluster is green
        STATUS=`curl -sS -XGET ${MASTER}/_cat/health | cut -f 4 -d ' '| grep green`
        COUNT=$((COUNT + 1))
        if [ $COUNT -gt 60 ]  && [ $ITERATIONS -lt 5 ]; then
            echo ">>>>>> Still waiting. verifying routing allocation enabled."
            UPDATE=`curl -sS -XPUT ${MASTER}/_cluster/settings -d '{ "transient" : { "cluster.routing.allocation.enable" : "all" } }'`

            COUNT=0
            ITERATIONS=$((ITERATIONS + 1))
        fi

        sleep 1
    done

    echo ">>>>>> Node ${NODE} restart completed at $(date)"
done
