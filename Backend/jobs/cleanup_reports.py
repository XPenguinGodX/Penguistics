import json
import logging
import os

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from models.Reports import Report

s3 = boto3.client('s3')
lambda_client = boto3.client('lambda')
logger = logging.getLogger(__name__)

REJECTED_RETENTION_DAYS = 3
PENDING_RERUN_HOURS = 24
IMAGE_PREFIX = 'PenguinAlbum/Potholes/'
S3_DELETE_BATCH = 1000


def delete_images(bucket, image_paths):
    keys = [path for path in image_paths if path and path.startswith(IMAGE_PREFIX)]
    for start in range(0, len(keys), S3_DELETE_BATCH):
        batch = keys[start:start + S3_DELETE_BATCH]
        try:
            result = s3.delete_objects(
                Bucket=bucket,
                Delete={'Objects': [{'Key': key} for key in batch], 'Quiet': True},
            )
        except (BotoCoreError, ClientError):
            logger.exception('Could not delete %d report images', len(batch))
            continue
        for error in result.get('Errors', []):
            logger.error('Could not delete %s: %s', error.get('Key'), error.get('Message'))


def rerun_validation(function_name, reports):
    rerun = 0
    for report in reports:
        try:
            lambda_client.invoke(
                FunctionName=function_name,
                InvocationType='Event',
                Payload=json.dumps({'report_id': str(report.id), 'image_key': report.imagepath}),
            )
            rerun += 1
        except (BotoCoreError, ClientError):
            logger.exception('Could not rerun validation for report %s', report.id)
    return rerun


def handler(event, context):
    bucket = os.environ.get('UPLOAD_BUCKET')
    validator = os.environ.get('VALIDATOR_FUNCTION_NAME')

    deleted_paths = Report.purge_expired(REJECTED_RETENTION_DAYS)
    if deleted_paths:
        if bucket:
            delete_images(bucket, deleted_paths)
        else:
            logger.error('UPLOAD_BUCKET is not configured; %d images were not deleted', len(deleted_paths))

    rerun = 0
    if validator:
        rerun = rerun_validation(validator, Report.get_stale_pending(PENDING_RERUN_HOURS))
    else:
        logger.warning('VALIDATOR_FUNCTION_NAME is not configured; skipping pending reruns')

    return {'deleted': len(deleted_paths), 'rerun': rerun}
