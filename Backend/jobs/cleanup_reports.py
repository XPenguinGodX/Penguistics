import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from models.Reports import Report

s3 = boto3.client('s3')
lambda_client = boto3.client('lambda')
# Geocoding waits for an answer, so give up quickly on a slow call instead of boto3's 60 seconds
geocode_client = boto3.client('lambda', config=Config(
    connect_timeout=2, read_timeout=6, retries={'total_max_attempts': 1}))
logger = logging.getLogger(__name__)

REJECTED_RETENTION_DAYS = 3
PENDING_RERUN_HOURS = 24
# Upload URLs expire after 5 minutes, so a day-old image no report points to was abandoned
ORPHAN_AGE_HOURS = 24
IMAGE_PREFIX = 'PenguinAlbum/Potholes/'
S3_DELETE_BATCH = 1000
# Reports geocoded per nightly run; the first run after schema v4 backfills old reports this many at a time
GEOCODE_BATCH = 200
# Failed lookups before a report keeps its profile city for good
GEOCODE_MAX_ATTEMPTS = 5
# Stop starting lookups when this little time is left, so the run finishes before its timeout
GEOCODE_TIME_RESERVE_MS = 10_000


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


def lookup_place(function_name, lat, long):
    """Ask GeocodeFunction about one point.

    Returns its answer ({"found": ..., "city": ..., "state": ...}),
    or None if the lookup failed and is worth trying again.
    """
    try:
        result = geocode_client.invoke(
            FunctionName=function_name,
            Payload=json.dumps({'lat': lat, 'long': long}),
        )
        answer = json.loads(result['Payload'].read())
    except (BotoCoreError, ClientError, KeyError, ValueError):
        logger.exception('Could not reach the geocoder for %s, %s', lat, long)
        return None
    if result.get('FunctionError') or not isinstance(answer, dict):
        return None
    return answer


def geocode_reports(function_name, context):
    """Give reports still using their reporter's profile city the city their pin is really in."""
    try:
        reports = Report.get_ungeocoded(GEOCODE_BATCH, GEOCODE_MAX_ATTEMPTS)
    except Exception:
        logger.exception('Could not load reports waiting for geocoding')
        return 0

    geocoded = 0
    for report in reports:
        if context is not None and context.get_remaining_time_in_millis() < GEOCODE_TIME_RESERVE_MS:
            logger.info('Out of time; the remaining reports are geocoded on the next run')
            break
        try:
            answer = lookup_place(function_name, report['lat'], report['long'])
            if answer and answer.get('found'):
                if Report.set_geocoded_location(report['id'], answer['city'], answer['state']):
                    geocoded += 1
            elif answer:
                # "No city here" will be the same answer tomorrow, so stop asking now
                Report.set_geocode_attempts(report['id'], GEOCODE_MAX_ATTEMPTS)
            else:
                Report.set_geocode_attempts(report['id'], report['geocode_attempts'] + 1)
        except Exception:
            # One bad report (or a database hiccup) must not stop the rest
            logger.exception('Could not geocode report %s', report['id'])
    return geocoded


def handler(event, context):
    bucket = os.environ.get('UPLOAD_BUCKET')
    validator = os.environ.get('VALIDATOR_FUNCTION_NAME')
    geocoder = os.environ.get('GEOCODER_FUNCTION_NAME')

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

    # Last, so purged reports aren't geocoded and a slow geocoder can't delay the other steps
    geocoded = 0
    if geocoder:
        geocoded = geocode_reports(geocoder, context)
    else:
        logger.warning('GEOCODER_FUNCTION_NAME is not configured; skipping geocoding')

    return {'deleted': len(deleted_paths), 'orphans': orphans, 'rerun': rerun, 'geocoded': geocoded}
