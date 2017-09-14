#!/bin/bash

# Example script to shutdown an elasticsearch node

set -e
set -u

# parameters from cli arg
IFS=',' read -r -a PARMS <<< "$1"
NODE=${PARMS[0]}
HOST=${PARMS[0]%%:*}  # keep everything before the ':', hostname
PORT=${PARMS[0]##*:}  # keep everything after the ':', port number
CLUSTER=${PARMS[1]}
SERVICE_NAME=${PARMS[3]}

echo "Shutting down ${NODE}"
echo "Host: ${HOST}"
echo "Port: ${PORT}"
echo "Cluster: ${CLUSTER}"
echo "Service Name: ${SERVICE_NAME}"
#
# must exit cleanly
exit 0
