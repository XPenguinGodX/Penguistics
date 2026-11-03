"""Exercise image validation with fake S3, ONNX Runtime, and Report model; never contact AWS."""
import io
import os
from pathlib import Path
import runpy
import sys
import types
import unittest
import uuid
from unittest.mock import Mock, patch

try:
    import numpy as np
    from PIL import Image, ImageOps  # noqa: F401  (loaded before sys.modules is patched)
except ImportError:  # pragma: no cover
    np = None

BACKEND = Path(__file__).resolve().parents[1]


class FakeClientError(Exception):
    def __init__(self, code):
        self.response = {"Error": {"Code": code}}


def jpeg_bytes():
    buffer = io.BytesIO()
    Image.new("RGB", (64, 48), (90, 90, 90)).save(buffer, format="JPEG")
    return buffer.getvalue()


def detect_output(scores, num_classes=1):
    """Fake YOLO detect output: (1, 4 + classes, candidates) with one candidate per score."""
    output = np.zeros((1, 4 + num_classes, 8400), dtype=np.float32)
    for candidate, (class_id, score) in enumerate(scores):
        output[0, 4 + class_id, candidate] = score
    return output


@unittest.skipIf(np is None, "numpy and Pillow are needed for validator tests")
class ValidateImageTests(unittest.TestCase):
    def setUp(self):
        self.report_id = uuid.uuid4()
        self.report = types.SimpleNamespace(
            id=self.report_id, status="PENDING", imagepath="PenguinAlbum/Potholes/photo.jpg")
        self.Report = Mock()
        self.Report.get_by_id.return_value = self.report

        self.s3 = Mock()
        self.s3.get_object.side_effect = lambda **_: {"Body": io.BytesIO(jpeg_bytes())}
        self.output = detect_output([(0, 0.9)])
        self.metadata = {"task": "detect", "names": "{0: 'pothole'}", "imgsz": "[640, 640]"}
        session = types.SimpleNamespace(
            get_inputs=lambda: [types.SimpleNamespace(name="images")],
            get_modelmeta=lambda: types.SimpleNamespace(custom_metadata_map=self.metadata),
            run=lambda outputs, feed: [self.output],
        )

        boto3 = types.ModuleType("boto3")
        boto3.client = Mock(return_value=self.s3)
        errors = types.ModuleType("botocore.exceptions")
        errors.ClientError = FakeClientError
        ort = types.ModuleType("onnxruntime")
        ort.InferenceSession = Mock(return_value=session)
        reports = types.ModuleType("models.Reports")
        reports.Report = self.Report
        modules = {"boto3": boto3, "botocore": types.ModuleType("botocore"),
                   "botocore.exceptions": errors, "onnxruntime": ort,
                   "models": types.ModuleType("models"), "models.Reports": reports}
        with patch.dict(sys.modules, modules), patch.object(sys, "path", [str(BACKEND), *sys.path]):
            self.handler = runpy.run_path(str(BACKEND / "scripts" / "validate_image.py"))["handler"]
        self.environment = patch.dict(os.environ, {"UPLOAD_BUCKET": "test-bucket", "MODEL_KEY": "model.onnx",
                                                   "CONFIDENCE_THRESHOLD": "0.5", "VALID_CLASSES": ""})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def invoke(self):
        return self.handler({"report_id": str(self.report_id)}, None)

    def resolved_as(self):
        args = self.Report.update_status.call_args.args
        return args[1], args[2]

    def test_confident_detection_confirms_report(self):
        self.assertEqual(self.invoke()["status"], "CONFIRMED")
        status, confidence = self.resolved_as()
        self.assertEqual(status, "CONFIRMED")
        self.assertAlmostEqual(confidence, 0.9, places=5)

    def test_weak_detection_rejects_report(self):
        self.output = detect_output([(0, 0.2)])
        self.assertEqual(self.invoke()["status"], "REJECTED")

    def test_only_valid_classes_count(self):
        self.metadata["names"] = "{0: 'pothole', 1: 'manhole'}"
        self.output = detect_output([(1, 0.95), (0, 0.1)], num_classes=2)
        with patch.dict(os.environ, {"VALID_CLASSES": "pothole"}):
            self.assertEqual(self.invoke()["status"], "REJECTED")

    def test_classification_models_are_supported(self):
        self.metadata.update(task="classify", names="{0: 'no_damage', 1: 'pothole'}", imgsz="224")
        self.output = np.array([[0.2, 0.8]], dtype=np.float32)
        with patch.dict(os.environ, {"VALID_CLASSES": "pothole"}):
            self.assertEqual(self.invoke()["status"], "CONFIRMED")

    def test_nms_free_models_are_supported(self):
        self.output = np.array([[[0, 0, 10, 10, 0.7, 0], [0, 0, 0, 0, 0.0, 0]]], dtype=np.float32)
        self.assertEqual(self.invoke()["status"], "CONFIRMED")

    def test_missing_photo_is_rejected_without_loading_model(self):
        self.s3.get_object.side_effect = FakeClientError("NoSuchKey")
        self.assertEqual(self.invoke()["status"], "REJECTED")
        self.assertEqual(self.resolved_as(), ("REJECTED", None))
        self.s3.download_file.assert_not_called()

    def test_files_that_are_not_images_are_rejected(self):
        self.s3.get_object.side_effect = lambda **_: {"Body": io.BytesIO(b"<html>not a photo</html>")}
        self.assertEqual(self.invoke()["status"], "REJECTED")

    def test_oversized_photos_are_rejected(self):
        self.s3.get_object.side_effect = lambda **_: {"Body": io.BytesIO(b"\0" * (10 * 1024 * 1024 + 1))}
        self.assertEqual(self.invoke()["status"], "REJECTED")

    def test_paths_outside_upload_folder_are_never_read(self):
        self.report.imagepath = "PenguinThirdEyeMkI.onnx"
        self.assertEqual(self.invoke()["status"], "REJECTED")
        self.s3.get_object.assert_not_called()

    def test_already_resolved_reports_are_skipped(self):
        self.report.status = "CONFIRMED"
        self.invoke()
        self.Report.update_status.assert_not_called()

    def test_temporary_s3_failures_raise_so_lambda_retries(self):
        self.s3.get_object.side_effect = FakeClientError("SlowDown")
        with self.assertRaises(FakeClientError):
            self.invoke()
        self.Report.update_status.assert_not_called()

    def test_invalid_event_is_ignored(self):
        self.assertIsNone(self.handler({"report_id": "nope"}, None)["status"])
        self.Report.get_by_id.assert_not_called()


if __name__ == "__main__":
    unittest.main()
