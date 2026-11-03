import json
import logging
import uuid

from models.Reports import Report

logger = logging.getLogger(__name__)


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


def handler(event, context):
    username = request_username(event)
    if not username:
        return response(401, {'message': 'Please log in to view reports.'})

    try:
        report_id = uuid.UUID((event.get('pathParameters') or {}).get('id', ''))
    except (TypeError, ValueError):
        return response(400, {'message': 'Unknown report id.'})

    try:
        report = Report.get_by_id(report_id)
    except Exception:
        logger.exception('Could not load report %s', report_id)
        return response(503, {'message': 'Reports are temporarily unavailable.'})

    # Same answer for "missing" and "someone else's" so ids cannot be probed
    if report is None or report.username != username:
        return response(404, {'message': 'Report not found.'})
    return response(200, report.to_dict())
