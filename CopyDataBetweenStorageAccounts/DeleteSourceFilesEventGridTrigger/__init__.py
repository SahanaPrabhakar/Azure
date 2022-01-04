import json
import logging
import os
import uuid
import sys
import azure.core
from azure.storage import blob
from azure.storage.blob import BlobClient
from azure.storage.blob import BlobLeaseClient
from azure.storage.blob import BlobServiceClient
from azure.storage.blob import ContainerClient
import azure.functions as func

import azure.functions as func
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
        dest_blob = BlobClient.from_connection_string(
                os.getenv("AZURE_STORAGE_DEST_CONNECTION_STRING"),
                target_container_name, blobname
                )
        dest_blob_properties = dest_blob.get_blob_properties()
        dest_blob_size = dest_blob_properties.size

        source_container = os.getenv("AZURE_SOURCE_CONTAINER")
        source_blob = BlobClient.from_connection_string(
                os.getenv("AZURE_STORAGE_CONNECTION_STRING"), 
                source_container, blobname
                )        
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
        source_container = os.getenv("AZURE_SOURCE_CONTAINER")
        source_blob = BlobClient.from_connection_string(
                os.getenv("AZURE_STORAGE_CONNECTION_STRING"), 
                source_container, blobname
                ) 

        # Lease the source blob for the delete        
        lease = BlobLeaseClient(source_blob)    
        lease.acquire()
        source_props = source_blob.get_blob_properties()
        
        if (source_props.lease.state == "leased"):            
            source_blob.delete_blob(lease=lease)
        
    except Exception as e:
        print("Exception in delete_blob_service: ", e)

  

