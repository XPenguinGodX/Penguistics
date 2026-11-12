import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from models.Reports import Report

s3 = boto3.client('s3')
lambda_client = boto3.client('lambda')
logger = logging.getLogger(__name__)

REJECTED_RETENTION_DAYS = 3
PENDING_RERUN_HOURS = 24
# Upload URLs expire after 5 minutes, so a day-old image no report points to was abandoned
ORPHAN_AGE_HOURS = 24
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


def delete_orphan_images(bucket):
    """Delete uploaded images older than ORPHAN_AGE_HOURS that no report points to."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=ORPHAN_AGE_HOURS)
    deleted = 0
    try:
        # S3 lists at most 1000 keys per page, the same size as one delete batch
        for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=IMAGE_PREFIX):
            old_keys = [item['Key'] for item in page.get('Contents', []) if item['LastModified'] < cutoff]
            orphans = sorted(set(old_keys) - Report.find_image_paths(old_keys))
            if orphans:
                delete_images(bucket, orphans)
                deleted += len(orphans)
    except (BotoCoreError, ClientError):
        logger.exception('Could not list report images for the orphan sweep')
    return deleted


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

    orphans = delete_orphan_images(bucket) if bucket else 0

    rerun = 0
    if validator:
        rerun = rerun_validation(validator, Report.get_stale_pending(PENDING_RERUN_HOURS))
    else:
        logger.warning('VALIDATOR_FUNCTION_NAME is not configured; skipping pending reruns')

    return {'deleted': len(deleted_paths), 'orphans': orphans, 'rerun': rerun}
