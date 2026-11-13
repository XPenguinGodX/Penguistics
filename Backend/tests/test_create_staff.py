"""Exercise CreateStaffFunction and SaveStaffFunction with fakes; never contact AWS or the database."""
import io
import os
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch

BACKEND = Path(__file__).resolve().parents[1]


class FakeBotoCoreError(Exception):
    pass


class FakeClientError(Exception):
    def __init__(self, code="SomethingFailed"):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


def staff_event(**overrides):
    event = {"username": "jdoe-slc", "email": "jdoe@slc.example", "firstname": " Jane ",
             "lastname": "Doe", "city": "  Salt   Lake City ", "state": "ut"}
    event.update(overrides)
    return event


class CreateStaffTests(unittest.TestCase):
    def setUp(self):
        self.cognito = Mock()
        self.lambda_client = Mock()
        self.lambda_client.invoke.return_value = {"Payload": io.BytesIO(b"{}")}
        boto3 = types.ModuleType("boto3")
        clients = {"cognito-idp": self.cognito, "lambda": self.lambda_client}
        boto3.client = Mock(side_effect=lambda service, **_: clients[service])
        errors = types.ModuleType("botocore.exceptions")
        errors.BotoCoreError = FakeBotoCoreError
        errors.ClientError = FakeClientError
        with patch.dict(sys.modules, {"boto3": boto3, "botocore": types.ModuleType("botocore"),
                                      "botocore.exceptions": errors}):
            self.handler = runpy.run_path(str(BACKEND / "scripts" / "create_staff.py"))["handler"]
        environment = patch.dict(os.environ, {"USER_POOL_ID": "pool-1",
                                              "SAVE_STAFF_FUNCTION_NAME": "test-save-staff"})
        environment.start()
        self.addCleanup(environment.stop)

    def test_creates_the_user_adds_the_group_and_saves_the_city(self):
        result = self.handler(staff_event(), None)
        self.assertEqual(result, {"created": True, "username": "jdoe-slc", "city": "Salt Lake City",
                                  "state": "Utah", "email_sent": True})
        create = self.cognito.admin_create_user.call_args.kwargs
        self.assertEqual(create["UserPoolId"], "pool-1")
        self.assertEqual(create["Username"], "jdoe-slc")
        attributes = {a["Name"]: a["Value"] for a in create["UserAttributes"]}
        self.assertEqual(attributes, {"email": "jdoe@slc.example", "email_verified": "true",
                                      "given_name": "Jane", "family_name": "Doe"})
        self.assertNotIn("MessageAction", create)
        self.cognito.admin_add_user_to_group.assert_called_once_with(
            UserPoolId="pool-1", Username="jdoe-slc", GroupName="CityStaff")
        invoke = self.lambda_client.invoke.call_args.kwargs
        self.assertEqual(invoke["FunctionName"], "test-save-staff")
        self.assertEqual(invoke["Payload"],
                         '{"username": "jdoe-slc", "city": "Salt Lake City", "state": "Utah"}')
        self.cognito.admin_delete_user.assert_not_called()

    def test_state_accepts_names_and_abbreviations(self):
        for given, expected in {"UT": "Utah", "utah": "Utah", " New  York ": "New York", "dc": "District of Columbia"}.items():
            with self.subTest(given):
                self.assertEqual(self.handler(staff_event(state=given), None)["state"], expected)

    def test_send_email_false_suppresses_the_invitation(self):
        result = self.handler(staff_event(send_email=False), None)
        self.assertFalse(result["email_sent"])
        self.assertEqual(self.cognito.admin_create_user.call_args.kwargs["MessageAction"], "SUPPRESS")

    def test_invalid_input_creates_nothing(self):
        cases = {"short username": {"username": "jd"}, "spaces in username": {"username": "jane doe"},
                 "bad email": {"email": "not-an-email"}, "no first name": {"firstname": "  "},
                 "no city": {"city": ""}, "long city": {"city": "x" * 101},
                 "unknown state": {"state": "Atlantis"}, "missing state": {"state": None}}
        for name, override in cases.items():
            with self.subTest(name):
                result = self.handler(staff_event(**override), None)
                self.assertFalse(result["created"])
                self.assertIn("error", result)
        self.cognito.admin_create_user.assert_not_called()

    def test_existing_username_is_a_clear_error(self):
        self.cognito.admin_create_user.side_effect = FakeClientError("UsernameExistsException")
        result = self.handler(staff_event(), None)
        self.assertFalse(result["created"])
        self.assertIn("already exists", result["error"])
        self.cognito.admin_add_user_to_group.assert_not_called()
        self.cognito.admin_delete_user.assert_not_called()

    def test_cognito_failures_are_reported(self):
        for error in (FakeClientError("InvalidParameterException"), FakeBotoCoreError()):
            with self.subTest(error=type(error).__name__):
                self.cognito.admin_create_user.side_effect = error
                self.assertFalse(self.handler(staff_event(), None)["created"])

    def test_failure_after_creating_the_user_removes_it(self):
        failures = {
            "group": lambda: setattr(self.cognito.admin_add_user_to_group, "side_effect", FakeClientError()),
            "database": lambda: setattr(self.lambda_client, "invoke", Mock(return_value={
                "FunctionError": "Unhandled", "Payload": io.BytesIO(b'{"errorMessage": "db down"}')})),
        }
        for name, break_it in failures.items():
            with self.subTest(name):
                self.cognito.reset_mock()
                self.cognito.admin_add_user_to_group.side_effect = None
                break_it()
                result = self.handler(staff_event(), None)
                self.assertFalse(result["created"])
                self.cognito.admin_delete_user.assert_called_once_with(UserPoolId="pool-1", Username="jdoe-slc")


class SaveStaffTests(unittest.TestCase):
    def setUp(self):
        self.cursor = Mock()
        self.conn = Mock(cursor=Mock(return_value=self.cursor))
        connection = types.ModuleType("database.connection")
        connection.get_db_connection = Mock(return_value=self.conn)
        with patch.dict(sys.modules, {"database": types.ModuleType("database"),
                                      "database.connection": connection}):
            module = runpy.run_path(str(BACKEND / "models" / "CityStaff.py"))
        self.handler = module["save_staff_handler"]
        self.CityStaff = module["CityStaff"]

    def test_saves_the_row_with_an_upsert(self):
        result = self.handler({"username": " jdoe-slc ", "city": "Salt Lake City", "state": "Utah"}, None)
        self.assertEqual(result, {"username": "jdoe-slc", "city": "Salt Lake City", "state": "Utah"})
        sql, params = self.cursor.execute.call_args.args
        self.assertIn("ON CONFLICT (username) DO UPDATE", sql)
        self.assertEqual(params, ("jdoe-slc", "Salt Lake City", "Utah"))
        self.conn.commit.assert_called_once()

    def test_missing_fields_raise_without_touching_the_database(self):
        for event in ({}, {"username": "jdoe", "city": "Provo"}, {"username": "jdoe", "city": " ", "state": "Utah"}, None):
            with self.subTest(event=event):
                with self.assertRaises(ValueError):
                    self.handler(event, None)
        self.cursor.execute.assert_not_called()

    def test_database_error_rolls_back_and_raises(self):
        self.cursor.execute.side_effect = RuntimeError("db down")
        with self.assertRaises(RuntimeError):
            self.handler({"username": "jdoe", "city": "Provo", "state": "Utah"}, None)
        self.conn.rollback.assert_called_once()

    def test_lookup_returns_none_for_non_staff(self):
        self.cursor.fetchone.return_value = None
        self.assertIsNone(self.CityStaff.get_by_username("alice"))
        self.cursor.fetchone.return_value = ("jdoe", "Provo", "Utah")
        self.assertEqual(self.CityStaff.get_by_username("jdoe").city, "Provo")


if __name__ == "__main__":
    unittest.main()
