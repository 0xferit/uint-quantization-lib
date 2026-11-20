import io
import json
import os
import unittest
from importlib import import_module
from unittest.mock import patch

publisher = import_module("scripts.publish-soldeer")


def response(metadata):
    return io.BytesIO(json.dumps(metadata).encode())


class SoldeerPublicationTest(unittest.TestCase):
    def test_empty_success_uploads_once_and_requires_visible_revision(self):
        missing = {"status": "success", "data": []}
        with (
            patch.object(publisher, "urlopen", side_effect=[response(missing), response(missing)]),
            patch.object(publisher.subprocess, "run") as upload,
            patch.dict(os.environ, {"SOLDEER_API_TOKEN": "test"}),
            self.assertRaisesRegex(SystemExit, "does not yet serve"),
        ):
            publisher.publish("1.0.0")
        upload.assert_called_once_with(
            ["forge", "soldeer", "push", f"{publisher.PACKAGE}~1.0.0", "--skip-warnings"], check=True
        )

    def test_invalid_registry_replies_never_trigger_an_upload(self):
        for metadata in (
            {"status": "fail", "data": []},
            {"status": "success", "data": {}},
            {"status": "success", "data": [{}, {}]},
            {"status": "success", "data": [{}]},
        ):
            with (
                self.subTest(metadata=metadata),
                patch.object(publisher, "urlopen", return_value=response(metadata)),
                patch.object(publisher.subprocess, "run") as upload,
                self.assertRaisesRegex(SystemExit, "Unexpected Soldeer"),
            ):
                publisher.publish("1.0.0")
            upload.assert_not_called()
