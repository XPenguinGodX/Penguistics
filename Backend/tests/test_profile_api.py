"""Exercise GET and PUT /profile with a fake User model; never contact AWS or the database."""
import json
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch

BACKEND = Path(__file__).resolve().parents[1]


def profile_event(method, username="alice", body=None):
    context = {"http": {"method": method}}
    if username:
        context["authorizer"] = {"jwt": {"claims": {"username": username}}}
    event = {"requestContext": context}
    if body is not None:
        event["body"] = body if isinstance(body, str) else json.dumps(body)
    return event


def fake_user(**overrides):
    fields = {"username": "alice", "firstName": "Alice", "lastName": "Liddell",
              "email": "alice@example.com", "state": "Utah", "city": "Salt Lake City"}
    fields.update(overrides)
    return Mock(**fields)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.User = Mock()
        self.User.get_by_username.return_value = fake_user()
        self.User.update_location.side_effect = (
            lambda username, state, city: fake_user(state=state, city=city))
        users = types.ModuleType("models.Users")
        users.User = self.User
        with patch.dict(sys.modules, {"models": types.ModuleType("models"), "models.Users": users}):
            self.handler = runpy.run_path(str(BACKEND / "scripts" / "user_profile.py"))["handler"]

    def put(self, body, username="alice"):
        return self.handler(profile_event("PUT", username, body), None)

    def test_get_returns_profile_without_email(self):
        result = self.handler(profile_event("GET"), None)
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(json.loads(result["body"]), {
            "username": "alice", "firstname": "Alice", "lastname": "Liddell",
            "state": "Utah", "city": "Salt Lake City"})
        self.User.get_by_username.assert_called_once_with("alice")

    def test_get_unknown_user_is_missing(self):
        self.User.get_by_username.return_value = None
        self.assertEqual(self.handler(profile_event("GET"), None)["statusCode"], 404)

    def test_put_updates_trimmed_state_and_city(self):
        result = self.put({"state": "  Idaho ", "city": "Coeur   d'Alene"})
        self.assertEqual(result["statusCode"], 200)
        self.User.update_location.assert_called_once_with("alice", "Idaho", "Coeur d'Alene")
        self.assertEqual(json.loads(result["body"])["city"], "Coeur d'Alene")

    def test_put_accepts_non_english_letters(self):
        self.assertEqual(self.put({"state": "São Paulo", "city": "Mogi das Cruzes"})["statusCode"], 200)

    def test_put_ignores_fields_other_than_state_and_city(self):
        self.put({"state": "Utah", "city": "Provo", "username": "mallory",
                  "firstname": "Eve", "email": "eve@example.com"})
        self.User.update_location.assert_called_once_with("alice", "Utah", "Provo")

    def test_put_rejects_bad_values_without_saving(self):
        cases = {"missing city": {"state": "Utah"},
                 "blank state": {"state": "   ", "city": "Provo"},
                 "too long": {"state": "Utah", "city": "x" * 101},
                 "digits": {"state": "Utah", "city": "Provo 84601"},
                 "markup": {"state": "Utah", "city": "<script>"},
                 "starts with punctuation": {"state": "-Utah", "city": "Provo"},
                 "not text": {"state": "Utah", "city": 42}}
        for name, body in cases.items():
            with self.subTest(name):
                self.assertEqual(self.put(body)["statusCode"], 400)
        self.assertEqual(self.put("not json")["statusCode"], 400)
        self.assertEqual(self.put(["Utah", "Provo"])["statusCode"], 400)
        self.User.update_location.assert_not_called()

    def test_put_unknown_user_is_missing(self):
        self.User.update_location.side_effect = None
        self.User.update_location.return_value = None
        self.assertEqual(self.put({"state": "Utah", "city": "Provo"})["statusCode"], 404)

    def test_database_failure_is_unavailable(self):
        self.User.get_by_username.side_effect = RuntimeError("db down")
        self.User.update_location.side_effect = RuntimeError("db down")
        self.assertEqual(self.handler(profile_event("GET"), None)["statusCode"], 503)
        self.assertEqual(self.put({"state": "Utah", "city": "Provo"})["statusCode"], 503)

    def test_missing_token_claims_are_unauthorized(self):
        self.assertEqual(self.handler(profile_event("GET", username=None), None)["statusCode"], 401)
        self.User.get_by_username.assert_not_called()

    def test_other_methods_are_not_allowed(self):
        self.assertEqual(self.handler(profile_event("DELETE"), None)["statusCode"], 405)


if __name__ == "__main__":
    unittest.main()
