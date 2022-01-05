import json
import logging
import os
from typing import Container
import uuid
import sys
import azure.core
from azure.storage import blob
from azure.storage.blob import BlobClient
from azure.storage.blob import BlobLeaseClient
from azure.storage.blob import BlobServiceClient
from azure.storage.blob import ContainerClient
import azure.functions as func
from azure.identity import ManagedIdentityCredential, ChainedTokenCredential
import time


def main(event: func.EventGridEvent):
    result = json.dumps({
        'id': event.id,
        'data': event.get_json(),
        'topic': event.topic,
        'subject': event.subject,
        'event_type': event.event_type,
    })

    tmpS = event.subject
    logging.info('Subject %s', tmpS)
    
    tmp = event.subject.split("/")
    target_container_name = tmp[4]    

    tmp = event.subject.split("blobs/")
    blobname = tmp[len(tmp)-1]    
       
    if(check_if_ready(target_container_name, blobname)):
        logging.info(f"Size match. Delete file.")
        delete_blob_source(blobname)
    
def check_if_ready(target_container_name, blobname):        

    try:
        managed_identity = ManagedIdentityCredential()
        credential_chain = ChainedTokenCredential(managed_identity)
        
        target_account_url=os.getenv("TARGET_ACCOUNT_URL")
        target_container_client = ContainerClient(account_url=target_account_url, container_name=target_container_name,credential=credential_chain)
        dest_blob = target_container_client.get_blob_client(blobname)           
        dest_blob_properties = dest_blob.get_blob_properties()
        dest_blob_size = dest_blob_properties.size

        source_account_url=os.getenv("SOURCE_ACCOUNT_URL")
        source_container = os.getenv("SOURCE_CONTAINER_NAME")
        source_container_client = ContainerClient(account_url=source_account_url, container_name=source_container,credential=credential_chain)
        source_blob = source_container_client.get_blob_client(blobname)                        
        source_blob_properties = source_blob.get_blob_properties()
        source_blob_size = source_blob_properties.size

        count = 0
        while(source_blob_size != dest_blob_size):
            time.sleep(10)
            count = count + 10
            # wait for 50 minutes to timeout
            if(count == 3000):
                return False
        
        return True
        
    except Exception as e:
        logging.exception(f"Function copy_container Exception: {e}")
        return False

def delete_blob_source(blobname): 
        
    try:
        
        managed_identity = ManagedIdentityCredential()
        credential_chain = ChainedTokenCredential(managed_identity)
        
        source_account_url=os.getenv("SOURCE_ACCOUNT_URL")
        source_container = os.getenv("SOURCE_CONTAINER_NAME")
        source_container_client = ContainerClient(account_url=source_account_url, container_name=source_container,credential=credential_chain)
        source_blob = source_container_client.get_blob_client(blobname) 

        # Lease the source blob for the delete        
        lease = BlobLeaseClient(source_blob)    
        lease.acquire()
        source_props = source_blob.get_blob_properties()
        
        if (source_props.lease.state == "leased"):            
            source_blob.delete_blob(lease=lease)
        
    except Exception as e:
        print("Exception in delete_blob_service: ", e) 

