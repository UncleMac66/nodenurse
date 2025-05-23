#!/usr/bin/env python3

import sys
import oci
import argparse

argparser = argparse.ArgumentParser()
argparser.add_argument('--instance-id', help='The OCID of the instance to tag')
argparser.add_argument('--check', action='store_true', help='Checks to see if the tag is properly set up')
argparser.add_argument('--setup', action='store_true', help='Creates and configures the proper tag/tag namespace')
args = argparser.parse_args()

signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()

region = signer.region

config = {'region': region, 'tenancy': signer.tenancy_id}


# Initialize the OCI ComputeClient
compute_client = oci.core.ComputeClient(config, signer=signer)
instance_ocid = args.instance_id

# Initialize the OCI IdentityClient
identity_client = oci.identity.IdentityClient(config, signer=signer)

def checktags():
    correct_namespace = ""
    good_namespace = False
    good_tag = False
    try:
        tag_namespaces = identity_client.list_tag_namespaces(signer.tenancy_id).data
        for tagns in tag_namespaces:
            if tagns.name == "ComputeInstanceHostActions":
                print(f"\nCorrect Tag Namespace Found...\n")
                correct_namespace = tagns.id
                good_namespace = True
        if not good_namespace:
            print(f"Tags are not set up properly...\n")
            sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

    try:
        tags = identity_client.list_tags(correct_namespace).data
        for tag in tags:
            if tag.name == "CustomerReportedHostStatus":
                print(f"Correct Tag Found...\n")
                good_tag = True
        if not good_tag:
            print(f"Tags are not set up properly...\n")
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

    if good_namespace and good_tag:
        print(f"Tags properly set up in {signer.tenancy_id}\n")
        sys.exit(0)

def createtag():

    try:
        create_tag_namespace_response = identity_client.create_tag_namespace(
        create_tag_namespace_details=oci.identity.models.CreateTagNamespaceDetails(
            compartment_id=signer.tenancy_id,
            name="ComputeInstanceHostActions",
            description="Compute Instance Actions Tag Namespace"
        ))
    
        # Get the data from response
        print(f"Created Tag Namespace: {create_tag_namespace_response.data.name}")
    
        create_tag_response = identity_client.create_tag(
    
            tag_namespace_id=create_tag_namespace_response.data.id,
            create_tag_details=oci.identity.models.CreateTagDetails(
                name="CustomerReportedHostStatus",
                description="Tag for reporting unhealthy instances"
            ))
    
        # Get the data from response
        print(f"Created Tag: {create_tag_response.data.name}")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if args.check:
    checktags()

if args.setup:
    createtag()

if args.instance_id:
    try:
        instance = compute_client.get_instance(instance_id=instance_ocid).data
        tags = instance.defined_tags
        tags.update({'ComputeInstanceHostActions': { 'CustomerReportedHostStatus': 'unhealthy' }})
        update_instance_details = oci.core.models.UpdateInstanceDetails(defined_tags=tags)
        print(f"Updating tags on instance: {instance_ocid}")
        compute_client.update_instance(instance_id=instance_ocid, update_instance_details=update_instance_details)

    except oci.exceptions.ServiceError as e:
        print(f"Error: {e}")
        sys.exit(1)

