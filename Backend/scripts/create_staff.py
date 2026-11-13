"""CreateStaffFunction: an admin runs this by hand to create a city staff account.

    aws lambda invoke --function-name <CreateStaffFunctionName> --payload fileb://staff.json out.json

staff.json:
    {"username": "jdoe-slc", "email": "jdoe@slc.gov", "firstname": "Jane", "lastname": "Doe",
     "city": "Salt Lake City", "state": "UT"}
Optional: "send_email": false skips Cognito's temporary-password email (set a password by hand instead).

It runs outside the VPC because Cognito is a public AWS API and the VPC has no internet.
The database row is written by SaveStaffFunction, which runs inside the VPC.
"""
import json
import logging
import os
import re

import boto3
from botocore.exceptions import BotoCoreError, ClientError

cognito = boto3.client('cognito-idp')
lambda_client = boto3.client('lambda')
logger = logging.getLogger(__name__)

STAFF_GROUP = 'CityStaff'
USERNAME = re.compile(r'[A-Za-z0-9._@+-]{3,100}')
EMAIL = re.compile(r'[^@\s]+@[^@\s]+\.[^@\s]+')

# Amazon Location returns full state names, so staff are stored the same way to match their reports
US_STATES = {
    'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California',
    'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware', 'DC': 'District of Columbia',
    'FL': 'Florida', 'GA': 'Georgia', 'HI': 'Hawaii', 'ID': 'Idaho', 'IL': 'Illinois',
    'IN': 'Indiana', 'IA': 'Iowa', 'KS': 'Kansas', 'KY': 'Kentucky', 'LA': 'Louisiana',
    'ME': 'Maine', 'MD': 'Maryland', 'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota',
    'MS': 'Mississippi', 'MO': 'Missouri', 'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada',
    'NH': 'New Hampshire', 'NJ': 'New Jersey', 'NM': 'New Mexico', 'NY': 'New York',
    'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio', 'OK': 'Oklahoma', 'OR': 'Oregon',
    'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina', 'SD': 'South Dakota',
    'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah', 'VT': 'Vermont', 'VA': 'Virginia',
    'WA': 'Washington', 'WV': 'West Virginia', 'WI': 'Wisconsin', 'WY': 'Wyoming',
}
# Lets "utah" or "UT" both become "Utah"
STATE_NAMES = {name.lower(): name for name in US_STATES.values()}


def clean(value):
    """Trim and collapse inner spaces (the same cleanup GeocodeFunction applies to city names)."""
    return ' '.join(value.split()) if isinstance(value, str) else ''


def state_name(value):
    value = clean(value)
    return US_STATES.get(value.upper()) or STATE_NAMES.get(value.lower())


def failed(message):
    return {'created': False, 'error': message}


def error_code(error):
    return getattr(error, 'response', {}).get('Error', {}).get('Code')


def save_staff_row(username, city, state):
    """Have SaveStaffFunction (inside the VPC) write the city_staff row. Raises if it fails."""
    result = lambda_client.invoke(
        FunctionName=os.environ['SAVE_STAFF_FUNCTION_NAME'],
        Payload=json.dumps({'username': username, 'city': city, 'state': state}),
    )
    if result.get('FunctionError'):
        raise RuntimeError(f"SaveStaffFunction failed: {result['Payload'].read().decode('utf-8', 'replace')}")


def handler(event, context):
    event = event if isinstance(event, dict) else {}
    username = clean(event.get('username'))
    email = clean(event.get('email'))
    firstname = clean(event.get('firstname'))
    lastname = clean(event.get('lastname'))
    city = clean(event.get('city'))
    state = state_name(event.get('state'))
    send_email = event.get('send_email', True) is not False

    if not USERNAME.fullmatch(username):
        return failed('username must be 3-100 letters, numbers, or . _ @ + -')
    if not EMAIL.fullmatch(email):
        return failed('email is not a valid address')
    if not firstname or not lastname:
        return failed('firstname and lastname are required')
    if not city or len(city) > 100:
        return failed('city is required (up to 100 characters), spelled as on a map, e.g. "Salt Lake City"')
    if state is None:
        return failed('state must be a US state name or abbreviation, e.g. "Utah" or "UT"')

    pool = os.environ['USER_POOL_ID']
    create = {
        'UserPoolId': pool,
        'Username': username,
        'UserAttributes': [
            {'Name': 'email', 'Value': email},
            # The admin vouches for the address, so "forgot password" works right away
            {'Name': 'email_verified', 'Value': 'true'},
            {'Name': 'given_name', 'Value': firstname},
            {'Name': 'family_name', 'Value': lastname},
        ],
        'DesiredDeliveryMediums': ['EMAIL'],
    }
    if not send_email:
        create['MessageAction'] = 'SUPPRESS'

    try:
        cognito.admin_create_user(**create)
    except ClientError as error:
        if error_code(error) == 'UsernameExistsException':
            return failed(f'user {username} already exists; pick another username')
        logger.exception('Could not create staff user %s', username)
        return failed(f'Cognito refused the new user: {error_code(error) or error}')
    except BotoCoreError:
        logger.exception('Could not reach Cognito')
        return failed('Could not reach Cognito; try again')

    # From here on, a failure deletes the new Cognito user, so a half-made account never lingers
    try:
        cognito.admin_add_user_to_group(UserPoolId=pool, Username=username, GroupName=STAFF_GROUP)
        save_staff_row(username, city, state)
    except Exception:
        logger.exception('Could not finish staff account %s; removing it', username)
        try:
            cognito.admin_delete_user(UserPoolId=pool, Username=username)
        except (BotoCoreError, ClientError):
            logger.exception('Could not remove half-created user %s; delete it by hand', username)
        return failed('Could not finish the account (see the function logs); nothing was kept')

    return {'created': True, 'username': username, 'city': city, 'state': state, 'email_sent': send_email}
