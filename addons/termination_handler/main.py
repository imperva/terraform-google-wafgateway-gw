import os
import base64
import json
import requests
import time
from enum import Enum
from urllib3.exceptions import InsecureRequestWarning

# Suppress insecure request warnings from urllib3
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)
MX_HOST = os.environ.get("MX_HOST")
MX_API_URL = f'https://{MX_HOST}:8083/SecureSphere/api/v1'

class APIError(Enum):
    GATEWAY_UP = 'IMP-10210'
    NOT_FOUND  = 'IMP-10102'

def create_api_session(retries=3, interval_s=5, request_timeout=10):
    session = requests.Session()    
    auth_response = session.post(f'{MX_API_URL}/auth/session', verify=False, auth=('admin', os.environ.get('MX_PASSWORD')), timeout=request_timeout)
    if auth_response.status_code == 200:
        return session
    else:
        retries -= 1
        if retries == 0:
            raise Exception(f'Authentication request to Management Server failed with status code {auth_response.status_code}')
        else:
            time.sleep(interval_s)
            return create_api_session(retries)
            

def delete_gateway(api_session, gateway_name, retries=6, interval_s=30, request_timeout=10):
    gw_delete_response = api_session.delete(f'{MX_API_URL}/conf/gateways/{gateway_name}', verify=False, timeout=request_timeout)
    if gw_delete_response.status_code == requests.codes.ok:        
        print(f"Gateway '{gateway_name}' has been removed successfully from the Management Server")
    else:
        error_code = gw_delete_response.json().get('errors', [{}])[0].get('error-code')

        # If the gateway isn't found, it was most likely deleted from the MX by its own shutdown scripts
        if error_code == APIError.NOT_FOUND.value:
            print(f"Gateway '{gateway_name}' has already removed itself from the Management Server")
        else:
            # The gateway could still be in 'Running' state when this function is executed, in which case the deletion will be retried a finite amount of times in constant intervals
            if error_code == APIError.GATEWAY_UP.value:
                print(f"Gateway '{gateway_name}' is still running")
            else:
                print(f"An unknown error has occurred while trying to delete '{gateway_name}'")
            
            retries -= 1
            if retries == 0:
                print(f"Gateway '{gateway_name}' could not be removed from the Management Server in a timely manner. Please see the function's execution logs")
            else:
                print(f'Waiting {interval_s} seconds before trying again (attempts left: {retries})...')
                time.sleep(interval_s)
                delete_gateway(api_session, gateway_name, retries)
                
def handler(event, context):
    """Triggered from a message on a Pub/Sub topic when a WAF Gateway instance in an auto-scaling instance group is deleted (for whatever reason).
    This Cloud Function makes sure that the gateway is fully deleted from the MX's inventory under any circumstances.
    In some cases, the gateway will be able to remove itself from the MX - this function takes care of the other cases.

    Args:
         event (dict): Event payload.
         context (google.cloud.functions.Context): Metadata for the event.
    """
    print(f'Creating session with Management Server host {MX_HOST}...')
    session = create_api_session()  
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')

    # Extract the gateway's name from the Pub/Sub message
    gateway_name = json.loads(pubsub_message)['protoPayload']['resourceName'].split('/')[-1]  
    delete_gateway(session, gateway_name)