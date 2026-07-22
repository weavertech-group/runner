#!/usr/bin/env python3

import base64
import hashlib
import hmac
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "report-lark.py"
SPEC = importlib.util.spec_from_file_location("report_lark", SCRIPT)
report_lark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report_lark)


class ReportLarkTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.environment = {
            "HOME": self.home.name,
            "GITHUB_REPOSITORY": "weavertech-group/runner",
            "GITHUB_RUN_ID": "123456",
            "SESSION_TARGET_ID": "repo-01",
            "SESSION_EVENT_NOW_EPOCH": "1784600000",
            "LARK_REPORTING_ENABLED": "true",
            "LARK_WEBHOOK_URL": "https://open.larksuite.com/open-apis/bot/v2/hook/test",
            "LARK_WEBHOOK_SECRET": "test-signing-secret",
        }

    def tearDown(self):
        self.home.cleanup()

    def payload(self, event):
        with patch.dict(os.environ, self.environment, clear=True):
            with patch.object(report_lark.urllib.request, "urlopen") as urlopen:
                report_lark.send(event)
                request = urlopen.call_args.args[0]
        return json.loads(request.data)

    def test_disabled_reporting_is_a_noop(self):
        environment = self.environment | {"LARK_REPORTING_ENABLED": "false"}
        with patch.dict(os.environ, environment, clear=True):
            with patch.object(report_lark.urllib.request, "urlopen") as urlopen:
                report_lark.send("starting")
                urlopen.assert_not_called()

    def test_starting_message_is_signed(self):
        payload = self.payload("starting")
        key = b"1784600000\ntest-signing-secret"
        signature = base64.b64encode(
            hmac.new(key, digestmod=hashlib.sha256).digest()
        ).decode()
        self.assertEqual(payload["sign"], signature)
        self.assertIn("Runner starting", payload["content"]["text"])
        self.assertIn("repo-01", payload["content"]["text"])

    def test_pairing_url_is_opt_in(self):
        session_dir = Path(self.home.name) / "private-runner-session" / "t3code"
        session_dir.mkdir(parents=True)
        (session_dir / "t3-url").write_text("https://t3.trycloudflare.com\n")
        (session_dir / "pairing-url").write_text("http://127.0.0.1:3773/pair\n")

        private_payload = self.payload("service-online")
        self.assertNotIn("127.0.0.1", private_payload["content"]["text"])

        self.environment["LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS"] = "true"
        shared_payload = self.payload("service-online")
        self.assertIn("127.0.0.1", shared_payload["content"]["text"])


if __name__ == "__main__":
    unittest.main()
