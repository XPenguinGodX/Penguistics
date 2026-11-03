import io
import logging
import os
import uuid

import boto3
from botocore.exceptions import ClientError
from PIL import Image, ImageOps, UnidentifiedImageError

from models.Reports import Report
from scripts.penguin_third_eye import PenguinThirdEye

s3 = boto3.client('s3')
logger = logging.getLogger(__name__)

IMAGE_PREFIX = 'PenguinAlbum/Potholes/'
MAX_IMAGE_BYTES = 10 * 1024 * 1024
IMAGE_FORMATS = {'JPEG', 'PNG', 'WEBP'}
MODEL_PATH = '/tmp/PenguinThirdEye.onnx'

_model = None


def load_model():
    """Download the ONNX model once per Lambda container and keep it in memory."""
    global _model
    if _model is None:
        if not os.path.exists(MODEL_PATH):
            s3.download_file(os.environ['UPLOAD_BUCKET'], os.environ['MODEL_KEY'], MODEL_PATH)
        valid_classes = [name.strip() for name in os.environ.get('VALID_CLASSES', '').split(',') if name.strip()]
        _model = PenguinThirdEye(MODEL_PATH, valid_classes)
    return _model


def load_photo(bucket, key):
    """Return the uploaded photo as RGB, or None if it is missing, too large, or not a real image."""
    try:
        body = s3.get_object(Bucket=bucket, Key=key)['Body']
    except ClientError as error:
        if error.response.get('Error', {}).get('Code') == 'NoSuchKey':
            return None
        raise

    data = body.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        return None
    try:
        photo = Image.open(io.BytesIO(data))
        if photo.format not in IMAGE_FORMATS:
            return None
        return ImageOps.exif_transpose(photo).convert('RGB')
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        return None


def handler(event, context):
    try:
        report_id = uuid.UUID(str(event.get('report_id')))
    except ValueError:
        logger.error('Validation event has no valid report_id: %s', event)
        return {'report_id': None, 'status': None}

    report = Report.get_by_id(report_id)
    if report is None or report.status != 'PENDING':
        # Async events can arrive more than once; only PENDING reports are scored
        logger.info('Report %s is missing or already resolved; skipping', report_id)
        return {'report_id': str(report_id), 'status': report.status if report else None}

    photo = None
    if report.imagepath.startswith(IMAGE_PREFIX):
        photo = load_photo(os.environ['UPLOAD_BUCKET'], report.imagepath)

    if photo is None:
        status, confidence = 'REJECTED', None
    else:
        confidence = load_model().confidence(photo)
        threshold = float(os.environ.get('CONFIDENCE_THRESHOLD', '0.35'))
        status = 'CONFIRMED' if confidence >= threshold else 'REJECTED'

    Report.update_status(report.id, status, confidence)
    logger.info('Report %s %s (confidence %s)', report.id, status, confidence)
    return {'report_id': str(report.id), 'status': status, 'confidence': confidence}
