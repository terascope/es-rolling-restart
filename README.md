# Elasticsearch cluster rolling restart script

This is a simple script to do a controlled rolling restart of a multinode elasticsearch cluster. It manages shard allocation and makes sure the cluster is in the proper status at each stage of the process.

## Parameters

* -m - MASTER - The master node to use for coordinating the update.
* -n - NODE_FILE - A file containing the list of node hostnames one per line.
* -s - SCRIPT - Script to run on each node to process the update. 

```
# ./rolling-restart.sh -m master1.example.com:9200 -n ./node-list.txt -s ./node-update.sh
```

### NODE_FILE

The node file is a list of node names (including HTTP port) one per line. These should only be nodes that contain data and the node list should not contain the host you're using as the master node.

NOTE: If you have dedicated master nodes, don't include them in the list. This script's primary purpose is to manage shard allocation which isn't necessary when restarting a dedicated master node. 

```
node1.example.com:9200
node2.example.com:9200
node3.example.com:9200
```

### SCRIPT

The script should contain the actions to perform on the stopped node. This assumes you have some sort of remote execution tool that can perform the update on the node. The script is run once for each node.

When the script runs the Elasticsearch instance on the node will already be stopped. It is the script's responsibility to restart it once updates are complete.

Two variables are made available to the script.

* $MASTER is the master node as provided on the command line.
* $NODE is the name of the node being restarted. This name will include the port.

```
#!/bin/bash
echo "Running updates on $NODE"

# Whatever commands are required should go here.

# Those commands should include starting the elasticsearch 
# instance once updates are complete.

exit 0
```

# Caveats

* The node provided as the master node should not occur in the list of nodes. To restart that node a second run would be required with it as the only node in the list and using a different node as the master.
* The script disables/enables shard allocation as it runs. If the script is interrupted while it's running shard allocation may remain disabled and should be re-enabled manually.
* If you have dedicated master nodes (and if you have enough nodes to need this script, you should) you need to restart those via a different mechanism.