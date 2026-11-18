"""Exercise the /city endpoints with fake CityStaff and Report models; never contact AWS or the database."""
import base64
import json
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch

BACKEND = Path(__file__).resolve().parents[1]


def city_event(username="jdoe", groups="[CityStaff]", status=None):
    claims = {}
    if username:
        claims["username"] = username
    if groups is not None:
        claims["cognito:groups"] = groups
    event = {"requestContext": {"authorizer": {"jwt": {"claims": claims}}}}
    if status is not None:
        event["queryStringParameters"] = {"status": status}
    return event


class CityReportsTests(unittest.TestCase):
    def setUp(self):
        self.CityStaff = Mock()
        self.CityStaff.get_by_username.return_value = Mock(city="Salt Lake City", state="Utah")
        self.Report = Mock()
        self.summaries = [{"id": "r1", "status": "CONFIRMED", "title": "Pothole"}]
        self.Report.get_city_summaries.return_value = self.summaries
        staff = types.ModuleType("models.CityStaff")
        staff.CityStaff = self.CityStaff
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        with patch.dict(sys.modules, {"models": types.ModuleType("models"),
                                      "models.CityStaff": staff, "models.Reports": reports}):
            self.handler = runpy.run_path(str(BACKEND / "scripts" / "city_reports.py"))["handler"]

    def call(self, **kwargs):
        result = self.handler(city_event(**kwargs), None)
        return result["statusCode"], json.loads(result["body"])

    def test_staff_get_their_citys_reports(self):
        code, body = self.call()
        self.assertEqual(code, 200)
        self.assertEqual(body, {"city": "Salt Lake City", "state": "Utah", "reports": self.summaries})
        self.CityStaff.get_by_username.assert_called_once_with("jdoe")
        self.Report.get_city_summaries.assert_called_once_with(
            "Salt Lake City", "Utah", ["CONFIRMED", "ACTIVE", "COMPLETED"])

    def test_city_always_comes_from_the_staff_record_never_the_request(self):
        # Asking for another city in the URL changes nothing: only the city_staff row decides
        event = city_event()
        event["queryStringParameters"] = {"city": "Provo", "state": "Utah"}
        self.assertEqual(self.handler(event, None)["statusCode"], 200)
        self.assertEqual(self.Report.get_city_summaries.call_args.args[:2], ("Salt Lake City", "Utah"))

    def test_users_outside_the_group_are_forbidden(self):
        for name, groups in {"no groups claim": None, "other group": "[Admins]",
                             "lookalike group": "[CityStaffers]", "empty": "[]"}.items():
            with self.subTest(name):
                self.assertEqual(self.call(groups=groups)[0], 403)
        self.CityStaff.get_by_username.assert_not_called()

    def test_group_claim_works_as_text_or_list(self):
        for groups in ("[CityStaff]", "[Admins CityStaff]", "CityStaff", ["Admins", "CityStaff"]):
            with self.subTest(groups=groups):
                self.assertEqual(self.call(groups=groups)[0], 200)

    def test_staff_without_a_city_are_forbidden(self):
        self.CityStaff.get_by_username.return_value = None
        self.assertEqual(self.call()[0], 403)
        self.Report.get_city_summaries.assert_not_called()

    def test_missing_username_is_unauthorized(self):
        self.assertEqual(self.call(username=None)[0], 401)

    def test_status_filter(self):
        cases = {"ACTIVE": ["ACTIVE"], "confirmed, active": ["CONFIRMED", "ACTIVE"],
                 "ACTIVE,ACTIVE": ["ACTIVE"]}
        for raw, expected in cases.items():
            with self.subTest(raw):
                self.assertEqual(self.call(status=raw)[0], 200)
                self.assertEqual(self.Report.get_city_summaries.call_args.args[2], expected)

    def test_dismissed_reports_only_appear_when_asked_for(self):
        self.call()
        self.assertNotIn("DISMISSED", self.Report.get_city_summaries.call_args.args[2])
        self.assertEqual(self.call(status="DISMISSED")[0], 200)
        self.assertEqual(self.Report.get_city_summaries.call_args.args[2], ["DISMISSED"])

    def test_statuses_the_city_never_sees_are_rejected(self):
        for raw in ("PENDING", "REJECTED", "ACTIVE,PENDING", "nonsense", " , "):
            with self.subTest(raw):
                self.assertEqual(self.call(status=raw)[0], 400)
        self.Report.get_city_summaries.assert_not_called()

    def test_database_failure_is_unavailable(self):
        self.Report.get_city_summaries.side_effect = RuntimeError("db down")
        self.assertEqual(self.call()[0], 503)


REPORT_ID = "6f1c2a34-1b2c-4d5e-8f90-123456789abc"


def status_event(new_status="ACTIVE", report_id=REPORT_ID, body=None, **kwargs):
    event = city_event(**kwargs)
    event["requestContext"]["http"] = {"method": "PUT"}
    event["pathParameters"] = {"id": report_id}
    event["body"] = body if body is not None else json.dumps({"status": new_status})
    return event


class ChangeStatusTests(unittest.TestCase):
    """PUT /city/reports/{id}/status: the same staff checks as the GET, plus the workflow rules."""

    def setUp(self):
        self.CityStaff = Mock()
        self.CityStaff.get_by_username.return_value = Mock(username="jdoe", city="Salt Lake City", state="Utah")
        self.Report = Mock()
        self.updated = {"id": REPORT_ID, "status": "ACTIVE"}
        self.Report.change_city_status.return_value = self.updated
        staff = types.ModuleType("models.CityStaff")
        staff.CityStaff = self.CityStaff
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        with patch.dict(sys.modules, {"models": types.ModuleType("models"),
                                      "models.CityStaff": staff, "models.Reports": reports}):
            self.handler = runpy.run_path(str(BACKEND / "scripts" / "city_reports.py"))["handler"]

    def call(self, *args, **kwargs):
        result = self.handler(status_event(*args, **kwargs), None)
        return result["statusCode"], json.loads(result["body"])

    def test_allowed_transitions(self):
        cases = {"ACTIVE": ["CONFIRMED"], "COMPLETED": ["ACTIVE"], "DISMISSED": ["CONFIRMED", "ACTIVE"]}
        for new_status, from_statuses in cases.items():
            with self.subTest(new_status):
                code, body = self.call(new_status)
                self.assertEqual(code, 200)
                self.assertEqual(body, {"report": self.updated})
                # The expected old statuses go into the UPDATE itself, which is what makes it atomic
                self.Report.change_city_status.assert_called_with(
                    REPORT_ID, "Salt Lake City", "Utah", from_statuses, new_status)

    def test_status_is_case_insensitive(self):
        self.assertEqual(self.call(" active ")[0], 200)
        self.assertEqual(self.Report.change_city_status.call_args.args[4], "ACTIVE")

    def test_disallowed_transitions_are_a_conflict(self):
        # (asked for, what the report really is): backwards, skipping ACTIVE, reopening, repeating
        cases = [("ACTIVE", "COMPLETED"), ("COMPLETED", "CONFIRMED"), ("ACTIVE", "DISMISSED"),
                 ("DISMISSED", "COMPLETED"), ("ACTIVE", "ACTIVE"), ("COMPLETED", "DISMISSED")]
        self.Report.change_city_status.return_value = None
        for new_status, current in cases:
            with self.subTest(f"{current} -> {new_status}"):
                self.Report.get_city_status.return_value = current
                code, body = self.call(new_status)
                self.assertEqual(code, 409)
                self.assertEqual(body["status"], current)

    def test_statuses_staff_cannot_set_are_bad_requests(self):
        for body in (json.dumps({"status": "CONFIRMED"}), json.dumps({"status": "PENDING"}),
                     json.dumps({"status": "REJECTED"}), json.dumps({}), json.dumps({"status": 5}),
                     json.dumps(["ACTIVE"]), "not json", ""):
            with self.subTest(body):
                self.assertEqual(self.handler(status_event(body=body), None)["statusCode"], 400)
        self.Report.change_city_status.assert_not_called()

    def test_base64_body_is_decoded(self):
        event = status_event(body=base64.b64encode(b'{"status": "ACTIVE"}').decode())
        event["isBase64Encoded"] = True
        self.assertEqual(self.handler(event, None)["statusCode"], 200)

    def test_report_in_another_city_is_not_found(self):
        self.Report.change_city_status.return_value = None
        self.Report.get_city_status.return_value = None
        self.assertEqual(self.call()[0], 404)
        self.Report.get_city_status.assert_called_once_with(REPORT_ID, "Salt Lake City", "Utah")

    def test_reports_hidden_from_the_city_are_not_found(self):
        # Answering 409 here would tell staff a PENDING or REJECTED report exists
        self.Report.change_city_status.return_value = None
        for hidden in ("PENDING", "REJECTED"):
            with self.subTest(hidden):
                self.Report.get_city_status.return_value = hidden
                self.assertEqual(self.call()[0], 404)

    def test_invalid_report_id_is_not_found_without_touching_the_database(self):
        for bad_id in ("not-a-uuid", "", "1; DROP TABLE reports"):
            with self.subTest(bad_id):
                self.assertEqual(self.call(report_id=bad_id)[0], 404)
        self.Report.change_city_status.assert_not_called()

    def test_same_staff_checks_as_the_list(self):
        self.assertEqual(self.call(groups="[Admins]")[0], 403)
        self.assertEqual(self.call(username=None)[0], 401)
        self.CityStaff.get_by_username.return_value = None
        self.assertEqual(self.call()[0], 403)
        self.Report.change_city_status.assert_not_called()

    def test_database_failure_is_unavailable(self):
        self.Report.change_city_status.side_effect = RuntimeError("db down")
        self.assertEqual(self.call()[0], 503)


class ChangeStatusQueryTests(unittest.TestCase):
    """Check the UPDATE itself: atomic status check, city scoping, and updated_at."""

    def setUp(self):
        self.cursor = Mock()
        self.cursor.fetchone.return_value = None
        self.conn = Mock(cursor=Mock(return_value=self.cursor))
        connection = types.ModuleType("database.connection")
        connection.get_db_connection = Mock(return_value=self.conn)
        with patch.dict(sys.modules, {"database": types.ModuleType("database"),
                                      "database.connection": connection}):
            self.Report = runpy.run_path(str(BACKEND / "models" / "Reports.py"))["Report"]

    def test_update_checks_the_old_status_and_city_in_the_same_statement(self):
        result = self.Report.change_city_status(REPORT_ID, "Salt Lake City", "Utah", ["CONFIRMED"], "ACTIVE")
        self.assertIsNone(result)
        sql, params = self.cursor.execute.call_args.args
        self.assertIn("UPDATE reports", sql)
        self.assertIn("status = ANY(%s::status[])", sql)
        self.assertIn("lower(trim(city)) = lower(trim(%s))", sql)
        self.assertIn("updated_at = now()", sql)
        self.assertEqual(params, ("ACTIVE", REPORT_ID, "Utah", "Salt Lake City", ["CONFIRMED"]))
        self.conn.commit.assert_called_once()

    def test_updated_row_comes_back_without_the_reporter(self):
        from datetime import datetime, timezone
        now = datetime(2026, 11, 14, tzinfo=timezone.utc)
        self.cursor.fetchone.return_value = (REPORT_ID, "ACTIVE", "Pothole", "Big one", 40.7, -111.9,
                                             0.9, "ONSITE", now, now)
        result = self.Report.change_city_status(REPORT_ID, "Salt Lake City", "Utah", ["CONFIRMED"], "ACTIVE")
        self.assertEqual(result["status"], "ACTIVE")
        self.assertEqual(result["updated_at"], now.isoformat())
        returned = self.cursor.execute.call_args.args[0].split("RETURNING")[1]
        self.assertNotIn("username", returned)
        self.assertNotIn("imagepath", returned)


class CitySummariesQueryTests(unittest.TestCase):
    """Check the SQL itself: case-insensitive city match, and no reporter identity in the result."""

    def setUp(self):
        self.cursor = Mock()
        self.cursor.fetchall.return_value = []
        connection = types.ModuleType("database.connection")
        connection.get_db_connection = Mock(return_value=Mock(cursor=Mock(return_value=self.cursor)))
        with patch.dict(sys.modules, {"database": types.ModuleType("database"),
                                      "database.connection": connection}):
            self.Report = runpy.run_path(str(BACKEND / "models" / "Reports.py"))["Report"]

    def test_query_matches_city_and_state_case_insensitively_and_hides_the_reporter(self):
        self.Report.get_city_summaries("salt lake city ", "UTAH", ["CONFIRMED"])
        sql, params = self.cursor.execute.call_args.args
        self.assertIn("lower(trim(city)) = lower(trim(%s))", sql)
        self.assertIn("lower(trim(state)) = lower(trim(%s))", sql)
        self.assertEqual(params[:3], ("UTAH", "salt lake city ", ["CONFIRMED"]))
        selected = sql.split("FROM")[0]
        self.assertNotIn("username", selected)
        self.assertNotIn("imagepath", selected)


class ReportPhotoTests(unittest.TestCase):
    def setUp(self):
        CityReportsTests.setUp(self)
        self.Report.get_city_image.return_value = f'PenguinAlbum/Potholes/{REPORT_ID}.jpg'
        self.s3 = Mock()
        self.s3.generate_presigned_url.return_value = 'https://example.test/signed-photo'

    def call_photo(self, report_id=REPORT_ID, **kwargs):
        event = city_event(**kwargs)
        event['routeKey'] = 'GET /city/reports/{id}/photo'
        event['pathParameters'] = {'id': report_id}
        config = types.ModuleType('botocore.config')
        config.Config = Mock()
        with patch.dict(sys.modules, {'boto3': Mock(client=Mock(return_value=self.s3)),
                                     'botocore': types.ModuleType('botocore'), 'botocore.config': config}), \
             patch.dict('os.environ', {'UPLOAD_BUCKET': 'test-bucket'}):
            result = self.handler(event, None)
        return result['statusCode'], json.loads(result['body'])

    def test_photo_is_city_scoped_and_url_expires(self):
        code, body = self.call_photo()
        self.assertEqual(code, 200)
        self.assertEqual(body['expiresIn'], 300)
        self.Report.get_city_image.assert_called_once_with(REPORT_ID, 'Salt Lake City', 'Utah')
        self.s3.generate_presigned_url.assert_called_once_with('get_object',
            Params={'Bucket': 'test-bucket', 'Key': f'PenguinAlbum/Potholes/{REPORT_ID}.jpg'},
            ExpiresIn=300, HttpMethod='GET')

    def test_other_city_missing_and_unsafe_keys_never_get_signed(self):
        for key in (None, '', 'PenguinThirdEyeMkI.onnx', 'PenguinAlbum/Potholes/../secret.jpg'):
            self.Report.get_city_image.return_value = key
            self.assertEqual(self.call_photo()[0], 404)
        self.s3.generate_presigned_url.assert_not_called()

    def test_invalid_id_and_non_staff_never_reach_photo_query(self):
        self.assertEqual(self.call_photo(report_id='bad')[0], 404)
        self.assertEqual(self.call_photo(groups=None)[0], 403)
        self.assertEqual(self.call_photo(username=None)[0], 401)
        self.CityStaff.get_by_username.return_value = None
        self.assertEqual(self.call_photo()[0], 403)
        self.Report.get_city_image.assert_not_called()

    def test_database_and_signing_errors_are_recoverable(self):
        self.Report.get_city_image.side_effect = RuntimeError('db down')
        self.assertEqual(self.call_photo()[0], 503)
        self.Report.get_city_image.side_effect = None
        self.s3.generate_presigned_url.side_effect = RuntimeError('sign failed')
        self.assertEqual(self.call_photo()[0], 503)


class ReportPhotoQueryTests(unittest.TestCase):
    def test_query_scopes_by_city_state_and_visible_statuses(self):
        CitySummariesQueryTests.setUp(self)
        self.cursor.fetchone.return_value = ('photo-key',)
        self.assertEqual(self.Report.get_city_image(REPORT_ID, 'Example', 'UT'), 'photo-key')
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('lower(trim(city)) = lower(trim(%s))', sql)
        self.assertIn('lower(trim(state)) = lower(trim(%s))', sql)
        self.assertIn('status = ANY(%s::status[])', sql)
        self.assertEqual(params, (REPORT_ID, 'Example', 'UT', ['CONFIRMED', 'ACTIVE', 'COMPLETED', 'DISMISSED']))
        self.cursor.close.assert_called_once()


class CityStatsTests(unittest.TestCase):
    def setUp(self):
        CityReportsTests.setUp(self)
        self.Report.get_city_stats.return_value = {'counts': {'CONFIRMED': 2}, 'daily': [], 'average_completion_seconds': None}

    def stats(self, **kwargs):
        event = city_event(**kwargs)
        event['routeKey'] = 'GET /city/stats'
        return self.handler(event, None)

    def test_city_is_from_staff_and_not_map_limits(self):
        result = self.stats()
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(json.loads(result['body'])['counts']['CONFIRMED'], 2)
        self.Report.get_city_stats.assert_called_once_with('Salt Lake City', 'Utah')
        self.Report.get_city_summaries.assert_not_called()

    def test_auth_and_failure(self):
        self.assertEqual(self.stats(groups=None)['statusCode'], 403)
        self.assertEqual(self.stats(username=None)['statusCode'], 401)
        self.Report.get_city_stats.assert_not_called()
        self.Report.get_city_stats.side_effect = RuntimeError('db down')
        self.assertEqual(self.stats()['statusCode'], 503)

    def test_aggregate_query_scopes_city_and_handles_empty_results(self):
        CitySummariesQueryTests.setUp(self)
        self.cursor.fetchone.return_value = (None, None, None)
        data = self.Report.get_city_stats('Example', 'UT')
        self.assertEqual(data['counts'], dict.fromkeys(['CONFIRMED', 'ACTIVE', 'COMPLETED', 'DISMISSED'], 0))
        self.assertEqual(data['daily'], [])
        self.assertIsNone(data['average_completion_seconds'])
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('lower(trim(city)) = lower(trim(%s))', sql)
        self.assertIn('lower(trim(state)) = lower(trim(%s))', sql)
        self.assertEqual(params[:2], ('Example', 'UT'))
        self.assertNotIn('LIMIT', sql)
        self.cursor.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
