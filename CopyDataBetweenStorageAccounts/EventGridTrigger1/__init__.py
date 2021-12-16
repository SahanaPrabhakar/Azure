import json
import logging
import os
import uuid
import sys
import azure.core
from azure.storage import blob
from azure.storage.blob import BlobClient
from azure.storage.blob import BlobLeaseClient
import azure.functions as func


def main(event: func.EventGridEvent):
    result = json.dumps({
        'id': event.id,
        'data': event.get_json(),
        'topic': event.topic,
        'subject': event.subject,
        'event_type': event.event_type,
    })

    logging.info('Python EventGrid trigger processed an event: %s', result)   

    #blob_copy(event.topic, event.subject)
    tmp = event.subject.split("/")
    containername = tmp[4]
    logging.info('Container name from event grid after split: %s', containername)

    tmp = event.subject.split("blobs/")
    blobname = tmp[len(tmp)-1]
    logging.info('Blob name from event grid after split: %s', blobname)
    blob_copy(containername, blobname)

def blob_copy(container_name, blob_name):

    logging.info('Printing variables container conn string: ' + os.getenv("AZURE_STORAGE_CONNECTION_STRING"))
    
    # Create a BlobClient from a connection string
    # retrieved from an environment variable named
    # AZURE_STORAGE_CONNECTION_STRING.
    source_blob = BlobClient.from_connection_string(
        os.getenv("AZURE_STORAGE_CONNECTION_STRING"), 
        container_name, blob_name
        )

    logging.info('source blob BlobClient object created')
    try:
        # Lease the source blob for the copy operation
        # to prevent another client from modifying it.
        lease = BlobLeaseClient(source_blob)    
        lease.acquire()

        # Get the source blob's properties and display the lease state.
        source_props = source_blob.get_blob_properties()
        print("Lease state: " + source_props.lease.state)

        # Create a BlobClient representing the
        # destination blob with a unique name.
        target_container_name = os.getenv("AZURE_TARGET_CONTAINER")
        dest_blob = BlobClient.from_connection_string(
            os.getenv("AZURE_STORAGE_DEST_CONNECTION_STRING"),
            target_container_name, blob_name
            )

        #logging.info('Target blob object: ' + target_container_name)
        #logging.info('Source blob url to copy from: ' + source_blob.url)
        # Start the copy operation.
        dest_blob.start_copy_from_url(source_blob.url)

        # Get the destination blob's properties to check the copy status.
        properties = dest_blob.get_blob_properties()
        copy_props = properties.copy

        # Display the copy status.
        print("Copy status: " + copy_props["status"])
        print("Copy progress: " + copy_props["progress"])
        print("Completion time: " + str(copy_props["completion_time"]))
        print("Total bytes: " + str(properties.size))
        
        # Run in premium and wait for completion, write to AI when complete
        # Cater for failure scenario,  dont wait forever
        # Use target blob trigger to delete, or use AI trigger/alert
        # az functionapp deployment source config-zip

        if (source_props.lease.state == "leased"):
            # Break the lease on the source blob.
            #source_blob.delete_blob(lease=lease)
            lease.break_lease()

            # Update the destination blob's properties to check the lease state.
            source_props = source_blob.get_blob_properties()
            print("Lease state: " + source_props.lease.state)

    except Exception as e:
        print("Exception: ", e)

  
