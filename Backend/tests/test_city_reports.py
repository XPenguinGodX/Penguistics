"""Exercise GET /city/reports with fake CityStaff and Report models; never contact AWS or the database."""
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

    def test_statuses_the_city_never_sees_are_rejected(self):
        for raw in ("PENDING", "REJECTED", "ACTIVE,PENDING", "nonsense", " , "):
            with self.subTest(raw):
                self.assertEqual(self.call(status=raw)[0], 400)
        self.Report.get_city_summaries.assert_not_called()

    def test_database_failure_is_unavailable(self):
        self.Report.get_city_summaries.side_effect = RuntimeError("db down")
        self.assertEqual(self.call()[0], 503)


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


if __name__ == "__main__":
    unittest.main()
