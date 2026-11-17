"""The city staff endpoints, all for reports in the calling employee's own city.

GET /city/reports               the reports for the city map
PUT /city/reports/{id}/status   move one report through the workflow
"""
import base64
import json
import logging
import os
import re
import uuid

from models.CityStaff import CityStaff
from models.Reports import Report

logger = logging.getLogger(__name__)

STAFF_GROUP = 'CityStaff'
# What the city works with. PENDING (still being checked) and REJECTED (not road damage) are noise to them.
CITY_STATUSES = ('CONFIRMED', 'ACTIVE', 'COMPLETED', 'DISMISSED')
# The map leaves out dismissed reports unless the staff member asks for them with ?status=DISMISSED
DEFAULT_STATUSES = ('CONFIRMED', 'ACTIVE', 'COMPLETED')
# The workflow: each new status, and the statuses a report may be in to move to it.
# Anything not listed here (going backwards, skipping ACTIVE, reopening a dismissed report) is a 409.
ALLOWED_TRANSITIONS = {
    'ACTIVE': ('CONFIRMED',),
    'COMPLETED': ('ACTIVE',),
    'DISMISSED': ('CONFIRMED', 'ACTIVE'),
}


def response(code, body):
    return {
        "statusCode": code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store"
        },
        "body": json.dumps(body)
    }


def token_claims(event):
    """The JWT claims the API Gateway authorizer already verified."""
    return event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {})


def token_groups(claims):
    """Read cognito:groups, which API Gateway hands over as text like "[CityStaff Admins]", not a list."""
    groups = claims.get('cognito:groups')
    if isinstance(groups, list):
        return {str(group) for group in groups}
    if isinstance(groups, str):
        return set(groups.strip('[]').replace(',', ' ').split())
    return set()


def requested_statuses(event):
    """Parse ?status=ACTIVE or ?status=CONFIRMED,ACTIVE. Returns None if any value isn't allowed."""
    raw = (event.get('queryStringParameters') or {}).get('status')
    if not raw:
        return list(DEFAULT_STATUSES)
    statuses = [value.strip().upper() for value in raw.split(',') if value.strip()]
    if not statuses or any(status not in CITY_STATUSES for status in statuses):
        return None
    # dict.fromkeys drops repeats but keeps the order
    return list(dict.fromkeys(statuses))


def request_body(event):
    """The JSON body as a dict, or None if it is missing or isn't a JSON object."""
    raw = event.get('body') or ''
    try:
        if event.get('isBase64Encoded'):
            raw = base64.b64decode(raw).decode('utf-8')
        body = json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        return None
    return body if isinstance(body, dict) else None


def calling_staff(event):
    """Check the caller is city staff with a city. Returns (staff, None) or (None, error response)."""
    claims = token_claims(event)
    username = claims.get('username') or claims.get('cognito:username')
    if not username:
        return None, response(401, {'message': 'Please log in to view city reports.'})
    if STAFF_GROUP not in token_groups(claims):
        return None, response(403, {'message': 'This account is not a city staff account.'})
    try:
        staff = CityStaff.get_by_username(username)
    except Exception:
        logger.exception('Could not look up city staff %s', username)
        return None, response(503, {'message': 'City reports are temporarily unavailable.'})
    if staff is None:
        # In the group but never assigned a city: show nothing rather than guess
        return None, response(403, {'message': 'This staff account has no city assigned yet.'})
    return staff, None


def list_reports(event, staff):
    statuses = requested_statuses(event)
    if statuses is None:
        return response(400, {'message': f'status must be one or more of: {", ".join(CITY_STATUSES)}.'})
    try:
        reports = Report.get_city_summaries(staff.city, staff.state, statuses)
    except Exception:
        logger.exception('Could not list city reports for %s', staff.username)
        return response(503, {'message': 'City reports are temporarily unavailable.'})
    return response(200, {'city': staff.city, 'state': staff.state, 'reports': reports})


def change_status(event, staff):
    raw_id = (event.get('pathParameters') or {}).get('id', '')
    try:
        report_id = str(uuid.UUID(raw_id))
    except ValueError:
        # Not even a valid id, so it can't be a report in this city
        return response(404, {'message': 'No report with that id in your city.'})

    body = request_body(event)
    new_status = body.get('status') if body else None
    new_status = new_status.strip().upper() if isinstance(new_status, str) else None
    if new_status not in ALLOWED_TRANSITIONS:
        return response(400, {'message': f'status must be one of: {", ".join(ALLOWED_TRANSITIONS)}.'})

    try:
        updated = Report.change_city_status(
            report_id, staff.city, staff.state, list(ALLOWED_TRANSITIONS[new_status]), new_status)
        if updated is not None:
            return response(200, {'report': updated})
        # Nothing changed: find out whether the report isn't ours to see (404) or just in the wrong state (409)
        current = Report.get_city_status(report_id, staff.city, staff.state)
    except Exception:
        logger.exception('Could not change report %s to %s for %s', report_id, new_status, staff.username)
        return response(503, {'message': 'City reports are temporarily unavailable.'})

    # PENDING and REJECTED reports are hidden from the city, so they get the same 404 as another city's
    if current not in CITY_STATUSES:
        return response(404, {'message': 'No report with that id in your city.'})
    return response(409, {
        'message': f'A {current} report can\'t be changed to {new_status}.',
        'status': current,
    })


def report_photo(event, staff):
    try:
        report_id = str(uuid.UUID((event.get('pathParameters') or {}).get('id', '')))
    except (ValueError, TypeError, AttributeError):
        return response(404, {'message': 'No photo for that report in your city.'})
    try:
        key = Report.get_city_image(report_id, staff.city, staff.state)
        if not isinstance(key, str) or not re.fullmatch(
                r'PenguinAlbum/Potholes/[0-9a-f-]{36}\.(jpg|png|webp)', key):
            return response(404, {'message': 'No photo for that report in your city.'})
        bucket = os.environ.get('UPLOAD_BUCKET')
        if not bucket:
            return response(503, {'message': 'Report photos are not configured.'})
        import boto3
        from botocore.config import Config
        s3 = boto3.client('s3', config=Config(signature_version='s3v4'))
        url = s3.generate_presigned_url('get_object',
            Params={'Bucket': bucket, 'Key': key}, ExpiresIn=300, HttpMethod='GET')
        return response(200, {'url': url, 'expiresIn': 300})
    except Exception:
        logger.exception('Could not load photo for report %s', report_id)
        return response(503, {'message': 'Report photos are temporarily unavailable.'})


def handler(event, context):
    staff, error = calling_staff(event)
    if error:
        return error
    method = event.get('requestContext', {}).get('http', {}).get('method', 'GET')
    if method == 'GET' and (event.get('routeKey', '').endswith('/photo') or
                            event.get('rawPath', '').endswith('/photo')):
        return report_photo(event, staff)
    if method == 'PUT':
        return change_status(event, staff)
    return list_reports(event, staff)
