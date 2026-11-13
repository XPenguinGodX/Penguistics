"""GET /city/reports: the reports in the calling city employee's city, for the city map."""
import json
import logging

from models.CityStaff import CityStaff
from models.Reports import Report

logger = logging.getLogger(__name__)

STAFF_GROUP = 'CityStaff'
# What the city works with. PENDING (still being checked) and REJECTED (not road damage) are noise to them.
CITY_STATUSES = ('CONFIRMED', 'ACTIVE', 'COMPLETED')


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
        return list(CITY_STATUSES)
    statuses = [value.strip().upper() for value in raw.split(',') if value.strip()]
    if not statuses or any(status not in CITY_STATUSES for status in statuses):
        return None
    # dict.fromkeys drops repeats but keeps the order
    return list(dict.fromkeys(statuses))


def handler(event, context):
    claims = token_claims(event)
    username = claims.get('username') or claims.get('cognito:username')
    if not username:
        return response(401, {'message': 'Please log in to view city reports.'})
    if STAFF_GROUP not in token_groups(claims):
        return response(403, {'message': 'This account is not a city staff account.'})

    statuses = requested_statuses(event)
    if statuses is None:
        return response(400, {'message': f'status must be one or more of: {", ".join(CITY_STATUSES)}.'})

    try:
        staff = CityStaff.get_by_username(username)
        if staff is None:
            # In the group but never assigned a city: show nothing rather than guess
            return response(403, {'message': 'This staff account has no city assigned yet.'})
        reports = Report.get_city_summaries(staff.city, staff.state, statuses)
    except Exception:
        logger.exception('Could not list city reports for %s', username)
        return response(503, {'message': 'City reports are temporarily unavailable.'})

    return response(200, {'city': staff.city, 'state': staff.state, 'reports': reports})
