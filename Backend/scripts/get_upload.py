import json
import logging
import os
import uuid

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

s3 = boto3.client('s3', config=Config(signature_version='s3v4'))
logger = logging.getLogger(__name__)
IMAGE_TYPES = {'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp'}


def response(code, body):
    return {
        "statusCode": code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store"
        },
        "body": json.dumps(body)
    }

def handler(event, context):
    query = event.get('queryStringParameters') or {}
    content_type = query.get('contentType', 'image/jpeg')
    if content_type not in IMAGE_TYPES:
        return response(400, {'message': 'Use image/jpeg, image/png, or image/webp.'})

    bucket = os.environ.get('UPLOAD_BUCKET')
    if not bucket:
        logger.error('UPLOAD_BUCKET is not configured')
        return response(500, {'message': 'Image uploads are not configured.'})

    key = f'PenguinAlbum/Potholes/{uuid.uuid4()}{IMAGE_TYPES[content_type]}'
    try:
        upload_url = s3.generate_presigned_url(
            'put_object',
            Params={'Bucket': bucket, 'Key': key, 'ContentType': content_type},
            ExpiresIn=300,
            HttpMethod='PUT',
        )
    except (BotoCoreError, ClientError):
        logger.exception('Could not generate an image upload URL')
        return response(503, {'message': 'Image uploads are temporarily unavailable.'})

    return response(200, {
        'url': upload_url,
        'key': key,
        'method': 'PUT',
        'headers': {'Content-Type': content_type},
        'expiresIn': 300,
    })
