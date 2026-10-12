import base64
import json
import mimetypes
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.meshy.ai/openapi"
KEY_FILE = Path.home() / ".local/nixlyos/meshy.key"
POLL_SECONDS = 5
HTTP_TOO_MANY_REQUESTS = 429
TERMINAL = {"SUCCEEDED", "FAILED", "CANCELED"}

mimetypes.add_type("model/gltf-binary", ".glb")


class ApiError(Exception):
    def __init__(self, code, message):
        super().__init__(f"{code} {message}" if code else message)
        self.code = code


def api_key():
    key = os.environ.get("MESHY_API_KEY", "")
    if not key and KEY_FILE.is_file():
        key = KEY_FILE.read_text().strip()
    if not key:
        raise ApiError(0, f"no API key; run `meshy key msy_...` (stored in {KEY_FILE})")
    return key


def save_key(key):
    KEY_FILE.parent.mkdir(parents=True, exist_ok=True)
    KEY_FILE.write_text(key + "\n")
    KEY_FILE.chmod(0o600)
    return KEY_FILE


def request(method, path, body=None):
    payload = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {api_key()}", "Content-Type": "application/json"}
    while True:
        req = urllib.request.Request(API + path, data=payload, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            if err.code != HTTP_TOO_MANY_REQUESTS:
                raise ApiError(err.code, error_message(err)) from None
            time.sleep(float(err.headers.get("Retry-After", POLL_SECONDS)))


def error_message(err):
    try:
        return json.load(err).get("message", err.reason)
    except ValueError:
        return err.reason


def wait(path, task_id):
    shown = None
    while True:
        task = request("GET", f"{path}/{task_id}")
        line = f"{task['status'].lower()} {task['progress']}%"
        if line != shown:
            print(f"{task_id} {line}", file=sys.stderr)
            shown = line
        if task["status"] == "SUCCEEDED":
            return task
        if task["status"] in TERMINAL:
            raise ApiError(0, f"task {task_id} {task['status']}: {(task.get('task_error') or {}).get('message', '')}")
        time.sleep(POLL_SECONDS)


def download(url, dest):
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(url, timeout=120) as resp, dest.open("wb") as out:
            shutil.copyfileobj(resp, out)
    except urllib.error.HTTPError as err:
        raise ApiError(err.code, f"download of {dest.name} refused") from None
    return str(dest)


def data_uri(path):
    mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
    return f"data:{mime};base64,{base64.b64encode(Path(path).read_bytes()).decode()}"
