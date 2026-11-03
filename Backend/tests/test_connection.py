"""Exercise database credential handling with fake Secrets Manager and pg8000; never contact AWS."""
import json
import os
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import Mock, patch

BACKEND = Path(__file__).resolve().parents[1]
SECRET_ARN = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-test"


class ConnectionTests(unittest.TestCase):
    def load(self, **environment):
        self.secrets = Mock()
        self.secrets.get_secret_value.return_value = {
            "SecretString": json.dumps({"username": "postgres", "password": "from-secrets-manager"})}
        boto3 = types.ModuleType("boto3")
        boto3.client = Mock(return_value=self.secrets)
        self.pg8000 = Mock()
        pg8000 = types.ModuleType("pg8000")
        pg8000.dbapi = self.pg8000
        modules = {"boto3": boto3, "pg8000": pg8000, "pg8000.dbapi": self.pg8000}
        db_keys = ("DB_HOST", "DB_PORT", "DB_NAME", "DB_SECRET_ARN", "DB_USER", "DB_PASSWORD")
        clean = {key: value for key, value in os.environ.items() if key not in db_keys}
        environment_patch = patch.dict(os.environ, {**clean, **environment}, clear=True)
        environment_patch.start()
        self.addCleanup(environment_patch.stop)
        with patch.dict(sys.modules, modules):
            self.module = runpy.run_path(str(BACKEND / "database" / "connection.py"))

    def connect_kwargs(self):
        return self.pg8000.connect.call_args.kwargs

    def test_rds_credentials_come_from_secrets_manager(self):
        self.load(DB_HOST="db.internal", DB_SECRET_ARN=SECRET_ARN)
        self.module["connect"]()
        self.secrets.get_secret_value.assert_called_once_with(SecretId=SECRET_ARN)
        self.assertEqual(self.connect_kwargs()["password"], "from-secrets-manager")
        self.assertIsNotNone(self.connect_kwargs()["ssl_context"])

    def test_remote_database_refuses_password_variables(self):
        self.load(DB_HOST="db.internal", DB_PASSWORD="plain-text")
        with self.assertRaises(RuntimeError):
            self.module["connect"]()
        self.pg8000.connect.assert_not_called()

    def test_local_database_can_use_password_variable(self):
        self.load(DB_HOST="localhost", DB_PASSWORD="local-only")
        self.module["connect"]()
        self.secrets.get_secret_value.assert_not_called()
        self.assertEqual(self.connect_kwargs()["password"], "local-only")
        self.assertIsNone(self.connect_kwargs()["ssl_context"])

    def test_each_new_connection_reads_the_current_secret(self):
        self.load(DB_HOST="db.internal", DB_SECRET_ARN=SECRET_ARN)
        self.module["connect"]()
        self.module["connect"]()
        self.assertEqual(self.secrets.get_secret_value.call_count, 2)

    def test_warm_invocations_reuse_one_connection(self):
        self.load(DB_HOST="db.internal", DB_SECRET_ARN=SECRET_ARN)
        first = self.module["get_db_connection"]()
        self.assertIs(self.module["get_db_connection"](), first)
        self.pg8000.connect.assert_called_once()


if __name__ == "__main__":
    unittest.main()
