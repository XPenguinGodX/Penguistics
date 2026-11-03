import json
import logging

from models.Users import User

logger = logging.getLogger(__name__)

MAX_PLACE_LENGTH = 100
PLACE_PUNCTUATION = " .'-"


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


def clean_place(value):
    """Tidy a state or city name, or return None if it isn't one.

    Letters in any alphabet are fine ("São Paulo"), plus space . ' - ("Coeur d'Alene").
    """
    if not isinstance(value, str):
        return None
    place = ' '.join(value.split())
    if not 1 <= len(place) <= MAX_PLACE_LENGTH or not place[0].isalpha():
        return None
    if not all(ch.isalpha() or ch in PLACE_PUNCTUATION for ch in place):
        return None
    return place


def public_profile(user):
    # Only what the profile page shows; email and the database id stay server-side
    return {
        'username': user.username,
        'firstname': user.firstName,
        'lastname': user.lastName,
        'state': user.state,
        'city': user.city,
    }


def get_profile(username):
    try:
        user = User.get_by_username(username)
    except Exception:
        logger.exception('Could not load profile for %s', username)
        return response(503, {'message': 'Your profile is temporarily unavailable.'})
    if user is None:
        return response(404, {'message': 'Profile not found.'})
    return response(200, public_profile(user))


def update_profile(username, raw_body):
    try:
        body = json.loads(raw_body or '')
    except (TypeError, ValueError):
        return response(400, {'message': 'Send state and city as JSON.'})
    if not isinstance(body, dict):
        return response(400, {'message': 'Send state and city as JSON.'})

    # Any other field in the body is ignored, so only state and city can change
    state = clean_place(body.get('state'))
    city = clean_place(body.get('city'))
    if state is None or city is None:
        return response(400, {
            'message': f'State and city are required, up to {MAX_PLACE_LENGTH} letters each.'
        })

    try:
        user = User.update_location(username, state, city)
    except Exception:
        logger.exception('Could not update profile for %s', username)
        return response(503, {'message': 'Your profile is temporarily unavailable.'})
    if user is None:
        return response(404, {'message': 'Profile not found.'})
    return response(200, public_profile(user))


def handler(event, context):
    username = request_username(event)
    if not username:
        return response(401, {'message': 'Please log in to view your profile.'})

    method = event.get('requestContext', {}).get('http', {}).get('method')
    if method == 'GET':
        return get_profile(username)
    if method == 'PUT':
        return update_profile(username, event.get('body'))
    return response(405, {'message': 'Method not allowed.'})
