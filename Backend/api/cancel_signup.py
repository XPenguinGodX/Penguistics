import base64
import hashlib
import hmac
import json
import os

import boto3
from botocore.exceptions import ClientError


def response(status, message):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": message}),
    }


def handler(event, context):
    try:
        body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body, validate=True).decode("utf-8")
        data = json.loads(body)
        if not isinstance(data, dict):
            return response(400, "Invalid cancellation request.")
        username = data.get("username")
        token = data.get("token")
        if (
            not isinstance(username, str) or not 1 <= len(username) <= 128
            or not isinstance(token, str) or len(token) != 43
        ):
            return response(400, "Invalid cancellation request.")
    except (ValueError, TypeError, UnicodeError):
        return response(400, "Invalid cancellation request.")

    cognito = boto3.client("cognito-idp")
    pool_id = os.environ["USER_POOL_ID"]
    try:
        user = cognito.admin_get_user(UserPoolId=pool_id, Username=username)
        attributes = {item["Name"]: item["Value"] for item in user["UserAttributes"]}
        expected = attributes.get("custom:signup_cancel_hash", "")
        supplied = hashlib.sha256(token.encode("utf-8")).hexdigest()
        if not expected or not hmac.compare_digest(expected, supplied):
            return response(403, "Unable to cancel this signup attempt.")
        if user["UserStatus"] != "UNCONFIRMED":
            return response(409, "This account is already confirmed. Please log in.")
        cognito.admin_delete_user(UserPoolId=pool_id, Username=user["Username"])
        return response(200, "Signup cancelled. You can try again.")
    except ClientError as error:
        if error.response["Error"]["Code"] == "UserNotFoundException":
            return response(200, "Signup cancelled. You can try again.")
        return response(503, "Cancellation is temporarily unavailable. Please retry.")
