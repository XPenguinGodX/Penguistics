"""Exercise cancellation with a fake Cognito client; never contact AWS."""
import base64
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch


class FakeClientError(Exception):
    def __init__(self, code):
        self.response = {"Error": {"Code": code}}


class CancelSignupTests(unittest.TestCase):
    def setUp(self):
        self.cognito = Mock()
        self.token = "a" * 43
        self.cognito.admin_get_user.return_value = {
            "Username": "canonical-user",
            "UserStatus": "UNCONFIRMED",
            "UserAttributes": [{
                "Name": "custom:signup_cancel_hash",
                "Value": hashlib.sha256(self.token.encode()).hexdigest(),
            }],
        }
        boto3 = types.ModuleType("boto3")
        boto3.client = Mock(return_value=self.cognito)
        errors = types.ModuleType("botocore.exceptions")
        errors.ClientError = FakeClientError
        modules = {"boto3": boto3, "botocore": types.ModuleType("botocore"),
                   "botocore.exceptions": errors}
        with patch.dict(sys.modules, modules):
            path = Path(__file__).resolve().parents[1] / "api" / "cancel_signup.py"
            self.handler = runpy.run_path(str(path))["handler"]
        self.environment = patch.dict(os.environ, {"USER_POOL_ID": "test-pool"})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def invoke(self, token=None):
        body = json.dumps({"username": "submitted-user", "token": token or self.token})
        return self.handler({"body": body}, None)

    def test_matching_secret_deletes_pending_user(self):
        self.assertEqual(self.invoke()["statusCode"], 200)
        self.cognito.admin_delete_user.assert_called_once_with(
            UserPoolId="test-pool", Username="canonical-user")

    def test_wrong_secret_cannot_delete(self):
        self.assertEqual(self.invoke("b" * 43)["statusCode"], 403)
        self.cognito.admin_delete_user.assert_not_called()

    def test_accounts_outside_unconfirmed_status_cannot_be_deleted(self):
        for status in ("CONFIRMED", "EXTERNAL_PROVIDER", "FORCE_CHANGE_PASSWORD"):
            with self.subTest(status=status):
                self.cognito.admin_get_user.return_value["UserStatus"] = status
                self.assertEqual(self.invoke()["statusCode"], 409)
                self.cognito.admin_delete_user.assert_not_called()

    def test_legacy_account_without_secret_cannot_be_deleted(self):
        self.cognito.admin_get_user.return_value["UserAttributes"] = []
        self.assertEqual(self.invoke()["statusCode"], 403)
        self.cognito.admin_delete_user.assert_not_called()

    def test_retry_after_deletion_is_successful(self):
        self.cognito.admin_get_user.side_effect = FakeClientError("UserNotFoundException")
        self.assertEqual(self.invoke()["statusCode"], 200)
        self.cognito.admin_delete_user.assert_not_called()

    def test_failed_deletion_does_not_report_success(self):
        self.cognito.admin_delete_user.side_effect = FakeClientError("AccessDeniedException")
        self.assertEqual(self.invoke()["statusCode"], 503)

    def test_invalid_requests_do_not_contact_cognito(self):
        for body in ("not json", "[]", "{}", '{"username": 7, "token": "short"}'):
            with self.subTest(body=body):
                self.assertEqual(self.handler({"body": body}, None)["statusCode"], 400)
        self.cognito.admin_get_user.assert_not_called()

    def test_base64_gateway_body_is_supported(self):
        body = json.dumps({"username": "submitted-user", "token": self.token})
        event = {"body": base64.b64encode(body.encode()).decode(), "isBase64Encoded": True}
        self.assertEqual(self.handler(event, None)["statusCode"], 200)


if __name__ == "__main__":
    unittest.main()
