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
import time

def main(event: func.EventGridEvent):
    result = json.dumps({
        'id': event.id,
        'data': event.get_json(),
        'topic': event.topic,
        'subject': event.subject,
        'event_type': event.event_type,
    })

    #logging.info(f'Event JSON is: {result}')
   
    tmp = event.subject.split("/")
    containername = tmp[4]   

    tmp = event.subject.split("blobs/")
    blobname = tmp[-1]    

    if(blobname.__contains__("Summary.txt")):
        logging.info(f'Found Summary.txt in blob name')     
        tmp = blobname.split("/")
        foldername = tmp[0]        
        copyContainer(containername, foldername)


def copyContainer(container_name, foldername):    
        
    blob_service_client = BlobServiceClient.from_connection_string(os.getenv("AZURE_STORAGE_CONNECTION_STRING"))
    
    # Instantiate a ContainerClient
    container_client = blob_service_client.get_container_client(container_name)    
    sourceBlobList = container_client.list_blobs()
    for blob in sourceBlobList:
       b_name = blob.name              
       if(b_name.__contains__(foldername)):
           logging.info(f'Initiaite copy : {b_name}')
           blob_copy(container_name, b_name)

def wait_for_copy(blob):
    count = 0
    props = blob.get_blob_properties()
    while props.copy.status == 'pending':
        count = count + 1
        if count > 50:
            raise TimeoutError('Timed out waiting for async copy to complete.')
        #time.sleep(60)
        #Testing time = 2s. Change later.
        time.sleep(2)
        props = blob.get_blob_properties()
    return props

def blob_copy(container_name, blob_name):

    source_blob = BlobClient.from_connection_string(
        os.getenv("AZURE_STORAGE_CONNECTION_STRING"), 
        container_name, blob_name
        )

    #logging.info('source blob BlobClient object created')
    try:
        # Lease the source blob for the copy operation
        # to prevent another client from modifying it.
        lease = BlobLeaseClient(source_blob)    
        lease.acquire()

        # Get the source blob's properties and display the lease state.
        source_props = source_blob.get_blob_properties()
        # Create a BlobClient representing the
        # destination blob with a unique name.
        target_container_name = os.getenv("AZURE_TARGET_CONTAINER")
        dest_blob = BlobClient.from_connection_string(
            os.getenv("AZURE_STORAGE_DEST_CONNECTION_STRING"),
            target_container_name, blob_name
            )

        # Start the copy operation.
        dest_blob.start_copy_from_url(source_blob.url)
        

        # Get the destination blob's properties to check the copy status.            
        wait_copy_data = wait_for_copy(dest_blob)
        logging.info(f'Copy status for {blob_name} is: {wait_copy_data.copy["status"]}')

        if (source_props.lease.state == "leased"):
            # Break the lease on the source blob.
            lease.break_lease(lease_break_period=1)
            #source_blob.delete_blob(lease=lease)
        
    except Exception as e:
        logging.exception(f"Function blob_copy Exception: {e}")
