# ./nodenurse.sh

Helper tool to test, diagnose, reboot, and tag unhealthy nodes in a slurm based GPU cluster. Specifically designed to work out of the box with GPU environments set up with [oci-hpc](https://github.com/oracle-quickstart/oci-hpc)


```
Usage: ./nodenurse.sh [OPTION] [ARGUMENT]

Description:
  nodenurse.sh takes supplied nodename(s), or a list of nodenames in a hostfile and can run a variety of functions
  on them which can be helpful when troubleshooting an OCI-HPC Slurm based cluster.

Options:
  -h, help             Display this message and exit.
  -c, healthcheck      Run a fresh healthcheck on the node(s).
  -l, latest           Gather the latest healthcheck from the node(s).
  -t, tag              Apply the unhealthy tag to the node(s)
  -r, reboot           Hard reboot the node(s).
  -e, exec             Execute command on the node(s)
  -i, identify         Display full details of the node(s) and exit.
  -n, nccl             Run allreduce nccl test on the node(s).
  -s, ncclscout        Run ncclscout (nccl pair test) on the node(s).
  -u, update           Update the slurm state on the node(s).
  -v, validate         Run nodes through checks to ensure ansible scripts will work.

Arguments:
  HOST(S)                An input hostfile, or space separated list of hostnames (e.g. gpu-1 gpu-2).

  --all,-a               Use all hosts that are listed in slurm.

  --idle                 Use hosts that are in a 'idle' state in slurm.

  --drain                Use hosts that are in a 'drain' state in slurm.

  --down                 Use hosts that are in a 'down' state in slurm.

  --alldown              Use hosts that are in a 'down' or 'drain' state in slurm.

  --maint                Use hosts that are in a 'maint' state in slurm.

  --partition,-p <name>  Use all nodes in a specified slurm partition name (i.e. compute).


Examples:
  ./nodenurse.sh -c <path/to/hostfile>    runs a fresh healthcheck on the node(s) in the provided hostlist.
  ./nodenurse.sh -r gpu-1                 sends a hard reboot signal to node 'gpu-1'.
  ./nodenurse.sh -v --all                 validates all nodes
  ./nodenurse.sh latest --alldown         grabs the latest healthchecks from nodes marked as drain or down in slurm.
  ./nodenurse.sh identify gpu-1 gpu-2     display details about 'gpu-1' and 'gpu-2' then quit.

Notes:
  - nodenurse.sh gets compartment OCID from /opt/oci-hpc/conf/queues.conf.
    If you use queues across compartments please double check this value and consider
    hard-coding it to your use case.

  - In order for tagging hosts as unhealthy to work properly, your tenancy must be properly
    whitelisted for unhealthy instance tagging.

  - nodenurse.sh deduplicates your provided hostlist.
```
