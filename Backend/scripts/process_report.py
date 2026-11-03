import base64
import binascii
import json
import logging
import math
import os
import re

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from models.Reports import Report
from models.Users import User

lambda_client = boto3.client('lambda')
logger = logging.getLogger(__name__)
IMAGE_KEY = re.compile(r'PenguinAlbum/Potholes/[0-9a-f-]{36}\.(jpg|png|webp)')
MAX_DESCRIPTION = 200


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


def handler(event, context):
    username = request_username(event)
    if not username:
        return response(401, {'message': 'Please log in before submitting a report.'})

    data = parse_body(event)
    if data is None:
        return response(400, {'message': 'Send the report as a JSON object.'})
    image_key = data.get('imagepath')
    description = data.get('description')
    long = coordinate(data.get('long'), 180)
    lat = coordinate(data.get('lat'), 90)
    if not isinstance(image_key, str) or not IMAGE_KEY.fullmatch(image_key):
        return response(400, {'message': 'Upload the image before submitting the report.'})
    if not isinstance(description, str) or not 0 < len(description.strip()) <= MAX_DESCRIPTION:
        return response(400, {'message': f'Description must be 1-{MAX_DESCRIPTION} characters.'})
    if long is None or lat is None:
        return response(400, {'message': 'A valid GPS location is required.'})

    try:
        user = User.get_by_username(username)
        if user is None:
            return response(403, {'message': 'Finish setting up your account before submitting reports.'})
        report = Report(
            username=username,
            imagepath=image_key,
            long=long,
            lat=lat,
            confidencelvl=None,
            description=description.strip(),
            city=user.city,
        )
        report.save()
    except Exception:
        logger.exception('Could not save report')
        return response(503, {'message': 'Reports are temporarily unavailable.'})

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
