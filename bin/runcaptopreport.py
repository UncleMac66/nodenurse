#!/usr/bin/python3
import oci
from datetime import datetime

capacity_topology_id="ocid1.computecapacitytopology.oc1.iad.aaaaaaaaaaaaa"
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
computeClient = oci.core.ComputeClient(config={}, signer=signer)

degraded_nodes=[]
count=0

print(datetime.now().strftime("%m/%d/%Y %H:%M:%S"))
print("----------------------\n     Block Status\n----------------------")
response=oci.pagination.list_call_get_all_results(computeClient.list_compute_capacity_topology_compute_bare_metal_hosts, capacity_topology_id)
state_counts={}
for node in response.data:
    status=node.lifecycle_details
    count+=1
    if status == "AVAILABLE" and not node.instance_id is None:
            status="RUNNING"
    if status == "DEGRADED":
        if not node.instance_id is None:
            status="RUNNING_DEGRADED"
        else:
            status="UNAVAILABLE_DEGRADED"
    if status in state_counts.keys():
        state_counts[status]+=1
    else:
        state_counts[status]=1
    if status == "RUNNING_DEGRADED":
        instance=computeClient.get_instance(node.instance_id)
        degraded_nodes.append({"ocid":node.instance_id,"name":instance.data.display_name})
print("State :: "+str(state_counts)+"\n")

print("Total ::", count)
