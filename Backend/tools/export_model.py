"""Run locally, not on Lambda: convert the trained YOLO model to ONNX and check it matches Ultralytics.

Needs: pip install ultralytics onnx onnxruntime
Usage (from Penguistics/Backend):
    python tools/export_model.py ../ModelArtifacts/PenguinThirdEyeMkI.pt [test_photo.jpg ...]

Keep model files out of Backend/: every CodeUri: . function would package them.
"""
import sys
from pathlib import Path

from PIL import Image, ImageOps
from ultralytics import YOLO

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.penguin_third_eye import PenguinThirdEye  # noqa: E402


def ultralytics_confidence(model, photo_path):
    result = model.predict(photo_path, conf=0.001, verbose=False)[0]
    if result.probs is not None:
        return float(result.probs.top1conf)
    return float(result.boxes.conf.max()) if len(result.boxes) else 0.0


def main(weights, photos):
    model = YOLO(weights)
    print(f'Task:    {model.task}')
    print(f'Classes: {model.names}')

    onnx_path = model.export(format='onnx', dynamic=False)
    onnx_model = YOLO(onnx_path, task=model.task)
    eye = PenguinThirdEye(onnx_path)
    for item in eye.session.get_inputs():
        print(f'Input  {item.name}: {item.shape}')
    for item in eye.session.get_outputs():
        print(f'Output {item.name}: {item.shape}')

    # pytorch uses rectangular input sizes, so it can differ a little on tall/wide photos.
    # ultralytics-onnx runs the same 640x640 graph as Lambda, so lambda should closely match it.
    for photo_path in photos:
        photo = ImageOps.exif_transpose(Image.open(photo_path)).convert('RGB')
        print(f'{photo_path}: pytorch={ultralytics_confidence(model, photo_path):.3f} '
              f'ultralytics-onnx={ultralytics_confidence(onnx_model, photo_path):.3f} '
              f'lambda={eye.confidence(photo):.3f}')

    print(f'\nUpload with: aws s3 cp "{onnx_path}" s3://firstpenguinbucket/{Path(onnx_path).name}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
