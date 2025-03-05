# oci-gpu-scripts


# ./nodenurse.sh
```
Usage: ./nodenurse.sh [OPTION] [HOST(S)]

Description:
./nodenurse.sh takes the nodes that are in a down/drain state in slurm, supplied nodename(s), or a hostfile and
can run a fresh healthcheck on them, grab the latest healthcheck, send them through ncclscout.py, or can be used
to initiate a hard reboot of those nodes.

Options:
-h, --help             Display this message and exit.
-c, --healthcheck      Run a fresh healthcheck on the node(s).
-l, --latest           Gather the latest healthcheck from the node(s).
-r, --reboot           Hard reboot the node(s).
-i, --identify         Display detail of the node(s) and exit.

Arguments:
HOST(S)                An input hostfile, or space separated list of hostnames (e.g. gpu-1 gpu-2).
                       This is optional. If no hosts are provided nodenurse will pull in nodes
                       that are in a down or drain state in slurm by default.

Examples:
./nodenurse.sh -c <path/to/hostfile>    runs a fresh healthcheck on the node(s) in the provided hostlist.
./nodenurse.sh -r gpu-1                 sends a hard reboot signal to node 'gpu-1'.
./nodenurse.sh -l                       grabs the latest healthchecks from nodes marked as drain or down in slurm.
./nodenurse.sh --identify gpu-1 gpu-2   display details about 'gpu-1' and 'gpu-2' then quit.
```

