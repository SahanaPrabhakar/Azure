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
        copy_container(containername, foldername)


def copy_container(container_name, foldername):    
        
    blob_service_client = BlobServiceClient.from_connection_string(os.getenv("AZURE_STORAGE_CONNECTION_STRING"))
    
    # Instantiate a ContainerClient
    container_client = blob_service_client.get_container_client(container_name)   
    # Get a list of all blobs.  
    sourceBlobList = container_client.list_blobs(foldername)        
    # TODO: Add pagination

    try:    
        count = 0
        for blob in sourceBlobList:
            b_name = blob.name              
            logging.info(f'Initiaite copy : {b_name}')        
            count = count+1
            blob_copy(container_name, b_name)

    except Exception as e:
        logging.exception(f"Function copy_container Exception: {e}")


def blob_copy(container_name, blob_name):

    source_blob = BlobClient.from_connection_string(
        os.getenv("AZURE_STORAGE_CONNECTION_STRING"), 
        container_name, blob_name
        )
    
    try:

        # No lease required as source blob will not change anymore
        
        # Create a BlobClient representing the
        # destination blob with a unique name.
        target_container_name = os.getenv("AZURE_TARGET_CONTAINER")
        dest_blob = BlobClient.from_connection_string(
            os.getenv("AZURE_STORAGE_DEST_CONNECTION_STRING"),
            target_container_name, blob_name
            )

        # Start the async copy operation.
        dest_blob.start_copy_from_url(source_blob.url)        
        
    except Exception as e:
        logging.exception(f"Function blob_copy Exception: {e}")
