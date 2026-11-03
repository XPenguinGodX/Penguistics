"""Exercise POST /reports and GET /reports/{id} with fake Lambda and models; never contact AWS."""
import json
import os
from pathlib import Path
import runpy
import sys
import types
import unittest
import uuid
from unittest.mock import Mock, patch

BACKEND = Path(__file__).resolve().parents[1]
IMAGE_KEY = f"PenguinAlbum/Potholes/{uuid.uuid4()}.jpg"


class FakeBotoCoreError(Exception):
    pass


class FakeClientError(Exception):
    pass


def jwt_event(username="alice", **extra):
    event = {"requestContext": {"authorizer": {"jwt": {"claims": {"username": username}}}}}
    event.update(extra)
    return event


def load_handler(script, modules):
    with patch.dict(sys.modules, modules):
        return runpy.run_path(str(BACKEND / "scripts" / script))["handler"]


class ProcessReportTests(unittest.TestCase):
    def setUp(self):
        self.lambda_client = Mock()
        self.report = Mock(id=uuid.uuid4(), status="PENDING")
        self.Report = Mock(return_value=self.report)
        self.User = Mock()
        self.User.get_by_username.return_value = Mock(city="Salt Lake City")

        boto3 = types.ModuleType("boto3")
        boto3.client = Mock(return_value=self.lambda_client)
        errors = types.ModuleType("botocore.exceptions")
        errors.BotoCoreError = FakeBotoCoreError
        errors.ClientError = FakeClientError
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        users = types.ModuleType("models.Users")
        users.User = self.User
        self.handler = load_handler("process_report.py", {
            "boto3": boto3, "botocore": types.ModuleType("botocore"), "botocore.exceptions": errors,
            "models": types.ModuleType("models"), "models.Reports": reports, "models.Users": users})
        self.environment = patch.dict(os.environ, {"VALIDATOR_FUNCTION_NAME": "test-validator"})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def invoke(self, username="alice", **overrides):
        body = {"imagepath": IMAGE_KEY, "lat": 40.76, "long": -111.89,
                "description": "  Deep pothole  ", "username": "mallory"}
        body.update(overrides)
        return self.handler(jwt_event(username, body=json.dumps(body)), None)

    def test_valid_report_is_saved_pending_and_validated_asynchronously(self):
        result = self.invoke()
        self.assertEqual(result["statusCode"], 202)
        self.assertEqual(json.loads(result["body"]), {"id": str(self.report.id), "status": "PENDING"})
        kwargs = self.Report.call_args.kwargs
        self.assertEqual((kwargs["username"], kwargs["city"]), ("alice", "Salt Lake City"))
        self.assertEqual(kwargs["description"], "Deep pothole")
        self.assertIsNone(kwargs["confidencelvl"])
        self.report.save.assert_called_once()
        self.lambda_client.invoke.assert_called_once_with(
            FunctionName="test-validator", InvocationType="Event",
            Payload=json.dumps({"report_id": str(self.report.id), "image_key": IMAGE_KEY}))

    def test_username_comes_from_token_not_body(self):
        self.invoke()
        self.User.get_by_username.assert_called_once_with("alice")

    def test_missing_token_claims_are_unauthorized(self):
        self.assertEqual(self.handler({"body": "{}"}, None)["statusCode"], 401)

    def test_invalid_reports_are_rejected_before_saving(self):
        cases = {"foreign key": {"imagepath": "PenguinThirdEyeMkI.onnx"},
                 "blank description": {"description": "   "},
                 "long description": {"description": "x" * 201},
                 "bad latitude": {"lat": 91},
                 "text longitude": {"long": "west"},
                 "boolean latitude": {"lat": True}}
        for name, override in cases.items():
            with self.subTest(name):
                self.assertEqual(self.invoke(**override)["statusCode"], 400)
        self.assertEqual(self.handler(jwt_event(body="not json"), None)["statusCode"], 400)
        self.report.save.assert_not_called()

    def test_users_missing_from_database_cannot_report(self):
        self.User.get_by_username.return_value = None
        self.assertEqual(self.invoke()["statusCode"], 403)
        self.report.save.assert_not_called()

    def test_database_failure_does_not_start_validation(self):
        self.report.save.side_effect = RuntimeError("db down")
        self.assertEqual(self.invoke()["statusCode"], 503)
        self.lambda_client.invoke.assert_not_called()

    def test_failed_validation_start_still_accepts_saved_report(self):
        self.lambda_client.invoke.side_effect = FakeClientError()
        self.assertEqual(self.invoke()["statusCode"], 202)


class GetReportTests(unittest.TestCase):
    def setUp(self):
        self.report_id = uuid.uuid4()
        self.report = Mock(username="alice")
        self.report.to_dict.return_value = {"id": str(self.report_id), "status": "CONFIRMED"}
        self.Report = Mock()
        self.Report.get_by_id.return_value = self.report
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        self.handler = load_handler("get_report.py", {
            "models": types.ModuleType("models"), "models.Reports": reports})

    def invoke(self, username="alice", report_id=None):
        return self.handler(jwt_event(username, pathParameters={"id": report_id or str(self.report_id)}), None)

    def test_owner_sees_report_status(self):
        result = self.invoke()
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(json.loads(result["body"])["status"], "CONFIRMED")

    def test_other_users_reports_look_missing(self):
        self.assertEqual(self.invoke(username="mallory")["statusCode"], 404)

    def test_unknown_report_is_missing(self):
        self.Report.get_by_id.return_value = None
        self.assertEqual(self.invoke()["statusCode"], 404)

    def test_malformed_id_is_rejected_without_querying(self):
        self.assertEqual(self.invoke(report_id="../etc")["statusCode"], 400)
        self.Report.get_by_id.assert_not_called()

    def test_missing_token_claims_are_unauthorized(self):
        self.assertEqual(self.handler({"pathParameters": {"id": str(self.report_id)}}, None)["statusCode"], 401)


class ListReportsTests(unittest.TestCase):
    def setUp(self):
        self.summaries = [{"id": str(uuid.uuid4()), "status": "PENDING", "description": "Pothole",
                           "lat": 40.76, "long": -111.89, "confidence": None,
                           "created_at": "2026-11-02T12:00:00+00:00"}]
        self.Report = Mock()
        self.Report.get_summaries_by_username.return_value = self.summaries
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        self.handler = load_handler("list_reports.py", {
            "models": types.ModuleType("models"), "models.Reports": reports})

    def test_lists_only_the_callers_reports(self):
        result = self.handler(jwt_event("alice"), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(json.loads(result["body"]), {"reports": self.summaries})
        self.Report.get_summaries_by_username.assert_called_once_with("alice")

    def test_no_reports_is_an_empty_list(self):
        self.Report.get_summaries_by_username.return_value = []
        self.assertEqual(json.loads(self.handler(jwt_event(), None)["body"]), {"reports": []})

    def test_database_failure_is_unavailable(self):
        self.Report.get_summaries_by_username.side_effect = RuntimeError("db down")
        self.assertEqual(self.handler(jwt_event(), None)["statusCode"], 503)

    def test_missing_token_claims_are_unauthorized(self):
        self.assertEqual(self.handler({}, None)["statusCode"], 401)
        self.Report.get_summaries_by_username.assert_not_called()


if __name__ == "__main__":
    unittest.main()
