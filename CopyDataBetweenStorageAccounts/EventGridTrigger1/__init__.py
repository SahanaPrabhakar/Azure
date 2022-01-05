import json
import logging
import os
import azure.core
from azure.storage import blob
from azure.storage.blob import BlobClient
from azure.storage.blob import BlobLeaseClient
from azure.storage.blob import BlobServiceClient
from azure.storage.blob import ContainerClient
import azure.functions as func
from azure.identity import ManagedIdentityCredential, ChainedTokenCredential

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
        copy_container( containername, foldername)


def copy_container(container_name, foldername):    
    try:
        # Get a token credential for authentication
   
        managed_identity = ManagedIdentityCredential()
        credential_chain = ChainedTokenCredential(managed_identity)
        # Instantiate a BlobServiceClient using a token credential    
        source_account_url=os.getenv("SOURCE_ACCOUNT_URL")
        source_blob_service_client = BlobServiceClient(account_url=source_account_url, credential=credential_chain)          
            
        # Instantiate a ContainerClient
        source_container_client = source_blob_service_client.get_container_client(container_name)   
        # Get a list of all blobs.  
        sourceBlobList = source_container_client.list_blobs(foldername)      

        target_account_url = os.getenv("TARGET_ACCOUNT_URL")
        target_container_name = os.getenv("TARGET_CONTAINER_NAME")
        target_container_client = ContainerClient(account_url=target_account_url, container_name=target_container_name,credential=credential_chain)
        
        count = 0
        # For loop will run through paginated response of ItemPaged
        for blob in sourceBlobList:
            b_name = blob.name              
            logging.info(f'Initiaite copy : {b_name}')        
            count = count+1
            blob_copy(source_container_client, b_name, target_container_client)

    except Exception as e:
        logging.exception(f"Function copy_container Exception: {e}")


def blob_copy(container_client, blob_name, target_container_client):

    source_blob = container_client.get_blob_client(blob_name)    
    
    try:

        # No lease required as source blob will not change anymore
        
        # Create a BlobClient 
        dest_blob = target_container_client.get_blob_client(blob_name)                   
        
        # Start the async copy operation.
        dest_blob.start_copy_from_url(source_blob.url)        
        
    except Exception as e:
        logging.exception(f"Function blob_copy Exception: {e}")
