#!/usr/bin/env python3

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.request
from pathlib import Path


def message(event: str) -> str:
    target = os.getenv("SESSION_TARGET_ID", "none")
    run_url = (
        f"{os.getenv('GITHUB_SERVER_URL', 'https://github.com')}/"
        f"{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    )

    if event == "starting":
        return f"Runner starting\nTarget: {target}\nRun: {run_url}"
    if event == "ssh-online":
        runner = os.getenv("SESSION_RUNNER_NAME", "unknown")
        return f"Runner SSH online\nTarget: {target}\nRunner: {runner}\nRun: {run_url}"
    if event == "setup-ready":
        ssh = os.getenv("SESSION_SSH_ONLINE", "false")
        return f"Runner ready\nTarget: {target}\nSSH: {ssh}\nRun: {run_url}"
    if event == "offline":
        return f"Runner offline\nTarget: {target}\nRun: {run_url}"
    if event == "service-online":
        session_dir = Path.home() / "private-runner-session" / "t3code"
        t3_url = (session_dir / "t3-url").read_text().strip()
        pairing = "available through SSH"
        if os.getenv("LARK_WEBHOOK_INCLUDE_TEMPORARY_ACCESS") == "true":
            pairing = (session_dir / "pairing-url").read_text().strip()
        return (
            f"T3 Code online\nTarget: {target}\nT3 URL: {t3_url}\n"
            f"Pairing URL: {pairing}\nRun: {run_url}"
        )
    raise ValueError(f"unknown event: {event}")


def send(event: str) -> None:
    if os.getenv("LARK_REPORTING_ENABLED") != "true":
        return

    timestamp = os.getenv("SESSION_EVENT_NOW_EPOCH", str(int(time.time())))
    signing_key = f"{timestamp}\n{os.environ['LARK_WEBHOOK_SECRET']}".encode()
    signature = base64.b64encode(
        hmac.new(signing_key, digestmod=hashlib.sha256).digest()
    ).decode()
    payload = json.dumps(
        {
            "timestamp": timestamp,
            "sign": signature,
            "msg_type": "text",
            "content": {"text": message(event)},
        }
    ).encode()
    request = urllib.request.Request(
        os.environ["LARK_WEBHOOK_URL"],
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request) as response:
        response.read()


if __name__ == "__main__":
    send(sys.argv[1])
