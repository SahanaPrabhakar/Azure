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

    tmp = blobname.split("/")
    foldername = tmp[0]

    # When any file arrives, check if NumberOfFiles exist. If not quit.
    # Then check the count of files with Number of Files.
    # If match then initiate delete of source files in foldername
    # Use list blobs and then delete
    # Register Event grid trigger in target container

    if(check_if_ready(target_container_name, foldername)):
        logging.info(f"Number of files matched. Ready to delete.")
        delete_blob_source(foldername)
    
def check_if_ready(target_container_name, foldername):        

    try:
        #BlobServiceClient for target storage account
        blob_service_client = BlobServiceClient.from_connection_string(os.getenv("AZURE_STORAGE_DEST_CONNECTION_STRING"))

        # Instantiate a ContainerClient for target container
        container_client = blob_service_client.get_container_client(target_container_name)                 
              
        #ItemsPaged iterator, Get all blobs in the folder
        targetBlobList = container_client.list_blobs(foldername)
        count = 0
        for i in targetBlobList:
            count = count+1
        if (count == 0):
            return False
    
        # If not returned yet, Number_of_files.txt exists.
        # Open file
        # Get the BlobClient from the ContainerClient to interact with a specific blob        
        number_of_file_blob_name = foldername + '/Number_of_files.txt'
        blob_client = container_client.get_blob_client(number_of_file_blob_name)
        data = blob_client.download_blob()
        numberoffiles = data.content_as_text(max_concurrency=1, encoding='UTF-8')
        logging.info(f'Number of files to match is : {numberoffiles}')
        logging.info(f'Count is: {count}')

        # Compare with count-1 (Original count does not include Number_of_files.txt)
        if (int(numberoffiles) == count-1):
            return True
   
        return False

    except Exception as e:
        logging.exception(f"Function copy_container Exception: {e}")
        return False

def delete_blob_source(foldername): 
        
    try:
        #BlobServiceClient for target storage account
        blob_service_client = BlobServiceClient.from_connection_string(os.getenv("AZURE_STORAGE_CONNECTION_STRING"))

        source_container = os.getenv("AZURE_SOURCE_CONTAINER")
        # Instantiate a ContainerClient for target container
        container_client = blob_service_client.get_container_client(source_container)                 
              
        #ItemsPaged iterator, Get all blobs in the folder
        sourceBlobList = container_client.list_blobs(foldername)
        for blob in sourceBlobList:
            logging.info(f'Deleting blob: {blob.name}')
            container_client.delete_blob(blob.name)
        
    except Exception as e:
        print("Exception in delete_blob_service: ", e)

  

