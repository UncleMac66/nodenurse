# oci-gpu-scripts


# ./nodenurse.sh
Usage: ./nodenurse.sh | -h [Run fresh healthchecks on node(s)] | -l [Get the latest healthcheck from the node(s)] | -r [Hard reset node(s)] | -i [Identify nodes] | <hostname, hostfile, or leave blank to pull down hosts from sinfo>

./nodenurse.sh takes the nodes that are in a down/drain state in slurm or a supplied nodename or hostfile and can run a fresh healthcheck on them, grab the latest healthcheck, send them through ncclscout.py, or can be used to initiate a hard reboot of those nodes.

Syntax: `./nodenurse.sh [option] [host or hostfile (optional)]`

For example:
```
./nodenurse.sh -h <path/to/hostfile> -> runs a fresh healthcheck on the node(s) in the provided hostlist

./nodenurse.sh -r gpu-123 -> sends a hard reboot signal to node 'gpu-123'

./nodenurse.sh -l -> grabs the latest healthchecks from nodes marked as drain or down in slurm
```

Todo:
- add ssh/gather facts testing to suite
- simplify options? 

