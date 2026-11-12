"""Turn a GPS point into the city and state it is in, using Amazon Location Service.

This Lambda runs outside the VPC because Amazon Location is a public AWS API and the
VPC has no internet. Lambdas inside the VPC invoke it through the Lambda VPC endpoint.

Event:   {"lat": 40.76, "long": -111.89}
Returns: {"found": true, "city": "Salt Lake City", "state": "Utah"}
         {"found": false, "city": null, "state": null}   (no city here, e.g. the ocean)
A failed Amazon Location call raises, so the caller sees a FunctionError and can retry later.
"""
import logging
import math

import boto3
from botocore.exceptions import BotoCoreError, ClientError

places = boto3.client('geo-places')
logger = logging.getLogger(__name__)


def coordinate(value, limit):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) and -limit <= value <= limit else None


def clean(name):
    """Trim and collapse inner spaces, so the same place always gives the same text."""
    if not isinstance(name, str):
        return None
    return ' '.join(name.split()) or None


def not_found():
    return {'found': False, 'city': None, 'state': None}


def handler(event, context):
    event = event if isinstance(event, dict) else {}
    lat = coordinate(event.get('lat'), 90)
    long = coordinate(event.get('long'), 180)
    if lat is None or long is None:
        return not_found()

    try:
        result = places.reverse_geocode(
            # Amazon Location takes [longitude, latitude], the reverse of how people say it
            QueryPosition=[long, lat],
            MaxResults=1,
            Language='en',
            # The answer is saved in the database; the default (SingleUse) does not allow storing it
            IntendedUse='Storage',
        )
    except (BotoCoreError, ClientError):
        logger.exception('Reverse geocoding failed for %s, %s', lat, long)
        raise

    items = result.get('ResultItems') or []
    address = (items[0].get('Address') or {}) if items else {}
    # Locality covers cities, towns, and villages; Region is the state
    city = clean(address.get('Locality'))
    state = clean((address.get('Region') or {}).get('Name'))
    if not city or not state:
        return not_found()
    return {'found': True, 'city': city, 'state': state}
