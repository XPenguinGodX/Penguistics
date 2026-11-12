import base64
import binascii
import json
import logging
import math
import os
import re
import uuid

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from models.Reports import Report
from models.Users import User

lambda_client = boto3.client('lambda')
s3 = boto3.client('s3')
logger = logging.getLogger(__name__)
IMAGE_KEY = re.compile(r'PenguinAlbum/Potholes/[0-9a-f-]{36}\.(jpg|png|webp)')
MAX_TITLE = 100
MAX_DESCRIPTION = 200
LOCATION_SOURCES = {'ONSITE', 'REMOTE'}
# A REMOTE pin must be this close to where the phone really is (roughly "the same city")
REMOTE_RADIUS_KM = 12
EARTH_RADIUS_KM = 6371.0


def response(code, body):
    return {
        "statusCode": code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store"
        },
        "body": json.dumps(body)
    }


def request_username(event):
    """Read the caller from the JWT the API Gateway authorizer already verified."""
    claims = event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {})
    return claims.get('username') or claims.get('cognito:username')


def parse_body(event):
    body = event.get('body') or ''
    try:
        if event.get('isBase64Encoded'):
            body = base64.b64decode(body, validate=True).decode('utf-8')
        data = json.loads(body)
    except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def coordinate(value, limit):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) and -limit <= value <= limit else None


def text(value, limit):
    """Return the trimmed string if it is 1 to `limit` characters long, else None."""
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value if 0 < len(value) <= limit else None


def distance_km(lat1, long1, lat2, long2):
    """Great-circle (haversine) distance between two GPS points, in kilometers."""
    lat1, long1, lat2, long2 = map(math.radians, (lat1, long1, lat2, long2))
    a = (math.sin((lat2 - lat1) / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin((long2 - long1) / 2) ** 2)
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def delete_old_image(image_key, new_key):
    """Best effort: a leftover image is removed later by the daily cleanup job anyway."""
    bucket = os.environ.get('UPLOAD_BUCKET')
    if not bucket or not image_key or image_key == new_key or not IMAGE_KEY.fullmatch(image_key):
        return
    try:
        s3.delete_object(Bucket=bucket, Key=image_key)
    except (BotoCoreError, ClientError):
        logger.exception('Could not delete replaced image %s', image_key)


def handler(event, context):
    username = request_username(event)
    if not username:
        return response(401, {'message': 'Please log in before submitting a report.'})

    data = parse_body(event)
    if data is None:
        return response(400, {'message': 'Send the report as a JSON object.'})
    image_key = data.get('imagepath')
    title = text(data.get('title'), MAX_TITLE)
    description = text(data.get('description'), MAX_DESCRIPTION)
    long = coordinate(data.get('long'), 180)
    lat = coordinate(data.get('lat'), 90)
    location_source = data.get('location_source', 'ONSITE')
    if not isinstance(image_key, str) or not IMAGE_KEY.fullmatch(image_key):
        return response(400, {'message': 'Upload the image before submitting the report.'})
    if title is None:
        return response(400, {'message': f'Title must be 1-{MAX_TITLE} characters.'})
    if description is None:
        return response(400, {'message': f'Description must be 1-{MAX_DESCRIPTION} characters.'})
    if long is None or lat is None:
        return response(400, {'message': 'A valid GPS location is required.'})
    if location_source not in LOCATION_SOURCES:
        return response(400, {'message': 'Unknown location source.'})

    device_long = device_lat = None
    if location_source == 'REMOTE':
        device_long = coordinate(data.get('device_long'), 180)
        device_lat = coordinate(data.get('device_lat'), 90)
        if device_long is None or device_lat is None:
            return response(400, {'message': "Your phone's GPS location is required for a remote report."})
        if distance_km(lat, long, device_lat, device_long) > REMOTE_RADIUS_KM:
            return response(400, {'message': f'Remote reports must be within {REMOTE_RADIUS_KM} km of you.'})

    replaces = None
    if data.get('replaces') is not None:
        try:
            replaces = uuid.UUID(str(data['replaces']))
        except ValueError:
            return response(400, {'message': 'Unknown report to replace.'})

    try:
        user = User.get_by_username(username)
        if user is None:
            return response(403, {'message': 'Finish setting up your account before submitting reports.'})
        report = Report(
            id=replaces,
            username=username,
            imagepath=image_key,
            long=long,
            lat=lat,
            confidencelvl=None,
            title=title,
            description=description,
            city=user.city,
            location_source=location_source,
            device_long=device_long,
            device_lat=device_lat,
        )
        old_image = report.retry_rejected() if replaces else None
        if old_image is None:
            # Not a retry, or the old report is gone/not theirs/not REJECTED: save a brand-new report
            report.id = uuid.uuid4()
            report.save()
    except Exception:
        logger.exception('Could not save report')
        return response(503, {'message': 'Reports are temporarily unavailable.'})

    if old_image is not None:
        delete_old_image(old_image, image_key)

    try:
        lambda_client.invoke(
            FunctionName=os.environ.get('VALIDATOR_FUNCTION_NAME'),
            InvocationType='Event',
            Payload=json.dumps({'report_id': str(report.id), 'image_key': image_key}),
        )
    except (BotoCoreError, ClientError):
        # The report is saved as PENDING; the daily cleanup job reruns it after 24 hours
        logger.exception('Could not start validation for report %s', report.id)

    return response(202, {'id': str(report.id), 'status': report.status})
