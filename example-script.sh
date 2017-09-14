#!/bin/bash

# Example script to restart an elasticsearch node
set -e
set -u

# parameters from cli arg
IFS=',' read -r -a PARMS <<< "$1"
NODE=${PARMS[0]}
HOST=${PARMS[0]%%:*}  # keep everything before the ':', hostname
PORT=${PARMS[0]##*:}  # keep everything after the ':', port number
CLUSTER=${PARMS[1]}
SERVICE=${PARMS[2]}
SERVICE_NAME=${PARMS[3]}

echo "Running updates on ${NODE}"
echo "Host: ${HOST}"
echo "Port: ${PORT}"
echo "Cluster: ${CLUSTER}"
echo "Service: ${SERVICE}"
echo "Service Name: ${SERVICE_NAME}"


# Whatever commands are required should go here.

# Those commands should include starting the elasticsearch
# instance once updates are complete.

exit 0
