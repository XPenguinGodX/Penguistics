"""Exercise the report cleanup job with fake S3, Lambda, and Report model; never contact AWS."""
import json
import os
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch


class FakeBotoCoreError(Exception):
    pass


class FakeClientError(Exception):
    pass


class CleanupReportsTests(unittest.TestCase):
    def setUp(self):
        self.s3 = Mock()
        self.s3.delete_objects.return_value = {}
        self.lambda_client = Mock()
        self.Report = Mock()
        self.Report.purge_expired.return_value = []
        self.Report.get_stale_pending.return_value = []

        boto3 = types.ModuleType("boto3")
        clients = {"s3": self.s3, "lambda": self.lambda_client}
        boto3.client = Mock(side_effect=lambda service, **_: clients[service])
        errors = types.ModuleType("botocore.exceptions")
        errors.BotoCoreError = FakeBotoCoreError
        errors.ClientError = FakeClientError
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        modules = {"boto3": boto3, "botocore": types.ModuleType("botocore"),
                   "botocore.exceptions": errors, "models": types.ModuleType("models"),
                   "models.Reports": reports}
        with patch.dict(sys.modules, modules):
            path = Path(__file__).resolve().parents[1] / "jobs" / "cleanup_reports.py"
            self.handler = runpy.run_path(str(path))["handler"]
        self.environment = patch.dict(os.environ, {"UPLOAD_BUCKET": "test-bucket",
                                                   "VALIDATOR_FUNCTION_NAME": "test-validator"})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def deleted_keys(self):
        return [obj["Key"] for call in self.s3.delete_objects.call_args_list
                for obj in call.kwargs["Delete"]["Objects"]]

    def test_expired_reports_use_three_day_window_and_remove_images(self):
        self.Report.purge_expired.return_value = ["PenguinAlbum/Potholes/a.jpg"]
        self.assertEqual(self.handler({}, None)["deleted"], 1)
        self.Report.purge_expired.assert_called_once_with(3)
        self.assertEqual(self.deleted_keys(), ["PenguinAlbum/Potholes/a.jpg"])

    def test_images_outside_upload_prefix_are_never_deleted(self):
        self.Report.purge_expired.return_value = ["PenguinAlbum/Potholes/a.jpg", "PenguinThirdEyeMkI.pt", ""]
        self.handler({}, None)
        self.assertEqual(self.deleted_keys(), ["PenguinAlbum/Potholes/a.jpg"])

    def test_nothing_expired_does_not_contact_s3(self):
        self.handler({}, None)
        self.s3.delete_objects.assert_not_called()

    def test_large_purges_are_split_into_s3_batches(self):
        self.Report.purge_expired.return_value = [f"PenguinAlbum/Potholes/{i}.jpg" for i in range(1001)]
        self.handler({}, None)
        self.assertEqual(self.s3.delete_objects.call_count, 2)

    def test_s3_failure_does_not_stop_pending_reruns(self):
        self.Report.purge_expired.return_value = ["PenguinAlbum/Potholes/a.jpg"]
        self.s3.delete_objects.side_effect = FakeClientError()
        self.Report.get_stale_pending.return_value = [Mock(id="r1", imagepath="PenguinAlbum/Potholes/r1.jpg")]
        self.assertEqual(self.handler({}, None)["rerun"], 1)

    def test_pending_reports_older_than_a_day_are_rerun_asynchronously(self):
        self.Report.get_stale_pending.return_value = [Mock(id="r1", imagepath="PenguinAlbum/Potholes/r1.jpg")]
        self.assertEqual(self.handler({}, None)["rerun"], 1)
        self.Report.get_stale_pending.assert_called_once_with(24)
        self.lambda_client.invoke.assert_called_once_with(
            FunctionName="test-validator",
            InvocationType="Event",
            Payload=json.dumps({"report_id": "r1", "image_key": "PenguinAlbum/Potholes/r1.jpg"}),
        )

    def test_one_failed_rerun_does_not_stop_the_others(self):
        self.Report.get_stale_pending.return_value = [Mock(id="r1", imagepath="k1"), Mock(id="r2", imagepath="k2")]
        self.lambda_client.invoke.side_effect = [FakeClientError(), None]
        self.assertEqual(self.handler({}, None)["rerun"], 1)
        self.assertEqual(self.lambda_client.invoke.call_count, 2)

    def test_reruns_are_skipped_until_validator_is_configured(self):
        with patch.dict(os.environ, {"VALIDATOR_FUNCTION_NAME": ""}):
            self.assertEqual(self.handler({}, None)["rerun"], 0)
        self.lambda_client.invoke.assert_not_called()


if __name__ == "__main__":
    unittest.main()
