import json
import logging

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
        reports = Report.get_summaries_by_username(username)
    except Exception:
        logger.exception('Could not list reports for %s', username)
        return response(503, {'message': 'Reports are temporarily unavailable.'})

    return response(200, {'reports': reports})
