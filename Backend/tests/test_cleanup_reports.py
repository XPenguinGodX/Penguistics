"""Exercise the report cleanup job with fake S3, Lambda, and Report model; never contact AWS."""
import io
import json
import os
from datetime import datetime, timedelta, timezone
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
        self.paginator = Mock()
        self.paginator.paginate.return_value = []
        self.s3.get_paginator.return_value = self.paginator
        self.lambda_client = Mock()
        self.Report = Mock()
        self.Report.purge_expired.return_value = []
        self.Report.get_stale_pending.return_value = []
        self.Report.find_image_paths.return_value = set()
        self.Report.get_ungeocoded.return_value = []
        self.Report.set_geocoded_location.return_value = True
        self.geocode_client = Mock()
        self.answer({"found": True, "city": "Provo", "state": "Utah"})

        boto3 = types.ModuleType("boto3")
        clients = {"s3": self.s3, "lambda": self.lambda_client}
        # The geocoder client is the Lambda client created with a short-timeout config
        boto3.client = Mock(side_effect=lambda service, **kwargs:
                            self.geocode_client if "config" in kwargs else clients[service])
        errors = types.ModuleType("botocore.exceptions")
        errors.BotoCoreError = FakeBotoCoreError
        errors.ClientError = FakeClientError
        config = types.ModuleType("botocore.config")
        config.Config = Mock()
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        modules = {"boto3": boto3, "botocore": types.ModuleType("botocore"),
                   "botocore.exceptions": errors, "botocore.config": config,
                   "models": types.ModuleType("models"),
                   "models.Reports": reports}
        with patch.dict(sys.modules, modules):
            path = Path(__file__).resolve().parents[1] / "jobs" / "cleanup_reports.py"
            self.handler = runpy.run_path(str(path))["handler"]
        self.environment = patch.dict(os.environ, {"UPLOAD_BUCKET": "test-bucket",
                                                   "VALIDATOR_FUNCTION_NAME": "test-validator",
                                                   "GEOCODER_FUNCTION_NAME": "test-geocoder"})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def answer(self, *answers):
        """Make the fake GeocodeFunction give these answers in order (an exception is raised instead)."""
        def response(answer):
            if isinstance(answer, Exception):
                return answer
            reply = {"Payload": io.BytesIO(json.dumps(answer).encode())}
            if answer.get("crashed"):
                reply["FunctionError"] = "Unhandled"
            return reply
        if len(answers) == 1 and not isinstance(answers[0], Exception):
            # The same answer for every call
            self.geocode_client.invoke.side_effect = lambda **_: response(answers[0])
        else:
            self.geocode_client.invoke.side_effect = [response(a) for a in answers]

    @staticmethod
    def waiting(report_id, attempts=0):
        return {"id": report_id, "lat": 40.23, "long": -111.66, "geocode_attempts": attempts}

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

    def test_old_images_no_report_points_to_are_deleted(self):
        now = datetime.now(timezone.utc)
        self.paginator.paginate.return_value = [{"Contents": [
            {"Key": "PenguinAlbum/Potholes/orphan.jpg", "LastModified": now - timedelta(days=2)},
            {"Key": "PenguinAlbum/Potholes/kept.jpg", "LastModified": now - timedelta(days=2)},
            {"Key": "PenguinAlbum/Potholes/fresh.jpg", "LastModified": now - timedelta(hours=1)},
        ]}]
        self.Report.find_image_paths.return_value = {"PenguinAlbum/Potholes/kept.jpg"}

        self.assertEqual(self.handler({}, None)["orphans"], 1)

        self.paginator.paginate.assert_called_once_with(Bucket="test-bucket", Prefix="PenguinAlbum/Potholes/")
        # A fresh upload may still be on its way to becoming a report, so it is not even checked
        self.Report.find_image_paths.assert_called_once_with(
            ["PenguinAlbum/Potholes/orphan.jpg", "PenguinAlbum/Potholes/kept.jpg"])
        self.assertEqual(self.deleted_keys(), ["PenguinAlbum/Potholes/orphan.jpg"])

    def test_orphan_listing_failure_does_not_stop_pending_reruns(self):
        self.paginator.paginate.side_effect = FakeClientError()
        self.Report.get_stale_pending.return_value = [Mock(id="r1", imagepath="PenguinAlbum/Potholes/r1.jpg")]
        result = self.handler({}, None)
        self.assertEqual((result["orphans"], result["rerun"]), (0, 1))

    def test_reruns_are_skipped_until_validator_is_configured(self):
        with patch.dict(os.environ, {"VALIDATOR_FUNCTION_NAME": ""}):
            self.assertEqual(self.handler({}, None)["rerun"], 0)
        self.lambda_client.invoke.assert_not_called()

    def test_reports_waiting_for_geocoding_get_their_real_city(self):
        self.Report.get_ungeocoded.return_value = [self.waiting("r1")]
        self.assertEqual(self.handler({}, None)["geocoded"], 1)
        self.Report.get_ungeocoded.assert_called_once_with(200, 5)
        self.assertEqual(json.loads(self.geocode_client.invoke.call_args.kwargs["Payload"]),
                         {"lat": 40.23, "long": -111.66})
        self.Report.set_geocoded_location.assert_called_once_with("r1", "Provo", "Utah")
        self.Report.set_geocode_attempts.assert_not_called()

    def test_failed_lookup_counts_an_attempt(self):
        cases = {"invoke error": FakeClientError(), "timeout": FakeBotoCoreError(),
                 "geocoder crashed": {"crashed": True, "errorMessage": "boom"}}
        for name, failure in cases.items():
            with self.subTest(name):
                self.Report.set_geocode_attempts.reset_mock()
                self.Report.get_ungeocoded.return_value = [self.waiting("r1", attempts=2)]
                self.answer(failure)
                self.assertEqual(self.handler({}, None)["geocoded"], 0)
                self.Report.set_geocode_attempts.assert_called_once_with("r1", 3)

    def test_no_city_at_the_pin_stops_retrying_at_once(self):
        self.Report.get_ungeocoded.return_value = [self.waiting("r1")]
        self.answer({"found": False, "city": None, "state": None})
        self.handler({}, None)
        self.Report.set_geocode_attempts.assert_called_once_with("r1", 5)
        self.Report.set_geocoded_location.assert_not_called()

    def test_one_failed_report_does_not_stop_the_others(self):
        self.Report.get_ungeocoded.return_value = [self.waiting("r1"), self.waiting("r2")]
        self.Report.set_geocoded_location.side_effect = [RuntimeError("db hiccup"), True]
        self.assertEqual(self.handler({}, None)["geocoded"], 1)
        self.assertEqual(self.Report.set_geocoded_location.call_count, 2)

    def test_report_geocoded_meanwhile_is_not_counted(self):
        self.Report.get_ungeocoded.return_value = [self.waiting("r1")]
        self.Report.set_geocoded_location.return_value = False
        self.assertEqual(self.handler({}, None)["geocoded"], 0)

    def test_geocoding_stops_when_the_run_is_almost_out_of_time(self):
        self.Report.get_ungeocoded.return_value = [self.waiting("r1"), self.waiting("r2"), self.waiting("r3")]
        context = Mock()
        context.get_remaining_time_in_millis.side_effect = [30_000, 9_000]
        self.assertEqual(self.handler({}, context)["geocoded"], 1)
        self.assertEqual(self.geocode_client.invoke.call_count, 1)

    def test_database_failure_loading_reports_does_not_crash_the_job(self):
        self.Report.get_ungeocoded.side_effect = RuntimeError("db down")
        self.Report.get_stale_pending.return_value = [Mock(id="r1", imagepath="PenguinAlbum/Potholes/r1.jpg")]
        result = self.handler({}, None)
        self.assertEqual((result["rerun"], result["geocoded"]), (1, 0))

    def test_geocoding_is_skipped_until_geocoder_is_configured(self):
        self.Report.get_ungeocoded.return_value = [self.waiting("r1")]
        with patch.dict(os.environ, {"GEOCODER_FUNCTION_NAME": ""}):
            self.assertEqual(self.handler({}, None)["geocoded"], 0)
        self.Report.get_ungeocoded.assert_not_called()
        self.geocode_client.invoke.assert_not_called()


if __name__ == "__main__":
    unittest.main()
