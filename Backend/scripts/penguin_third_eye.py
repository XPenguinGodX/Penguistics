import ast

import numpy as np
import onnxruntime as ort
from PIL import Image

LETTERBOX_FILL = (114, 114, 114)


class PenguinThirdEye:
    """Runs the Ultralytics-exported ONNX model and scores how likely a photo shows road damage."""

    def __init__(self, model_path, valid_classes=()):
        self.session = ort.InferenceSession(model_path, providers=['CPUExecutionProvider'])
        self.input_name = self.session.get_inputs()[0].name

        metadata = self.session.get_modelmeta().custom_metadata_map
        if 'names' not in metadata:
            raise ValueError('Model has no class names; export it with Ultralytics.')
        self.task = metadata.get('task', 'detect')
        self.names = ast.literal_eval(metadata['names'])
        imgsz = ast.literal_eval(metadata.get('imgsz', '[640, 640]'))
        height, width = (imgsz, imgsz) if isinstance(imgsz, int) else imgsz
        self.size = (width, height)

        wanted = set(valid_classes)
        unknown = wanted - set(self.names.values())
        if unknown:
            raise ValueError(f'Model has no classes named {sorted(unknown)}')
        self.class_ids = [i for i, name in self.names.items() if not wanted or name in wanted]

    def prepare(self, photo):
        """Resize an RGB photo the way Ultralytics does and return a (1, 3, H, W) float array."""
        width, height = self.size
        if self.task == 'classify':
            # Scale the short side to fit, then center-crop
            scale = max(width / photo.width, height / photo.height)
            resized = photo.resize((round(photo.width * scale), round(photo.height * scale)), Image.BILINEAR)
            left, top = (resized.width - width) // 2, (resized.height - height) // 2
            canvas = resized.crop((left, top, left + width, top + height))
        else:
            # Letterbox: scale the long side to fit, then pad with gray
            scale = min(width / photo.width, height / photo.height)
            resized = photo.resize(
                (max(1, round(photo.width * scale)), max(1, round(photo.height * scale))), Image.BILINEAR)
            canvas = Image.new('RGB', self.size, LETTERBOX_FILL)
            canvas.paste(resized, ((width - resized.width) // 2, (height - resized.height) // 2))

        pixels = np.asarray(canvas, dtype=np.float32) / 255.0
        return pixels.transpose(2, 0, 1)[np.newaxis]

    def confidence(self, photo) -> float:
        """Highest score the model gives any of the valid classes, from 0.0 to 1.0."""
        output = self.session.run(None, {self.input_name: self.prepare(photo)})[0]

        if self.task == 'classify':
            # (1, num_classes) probabilities
            return float(output[0, self.class_ids].max())

        if output.shape[2] == 6:
            # NMS-free export: (1, max_detections, [x1, y1, x2, y2, score, class])
            rows = output[0]
            keep = np.isin(rows[:, 5].astype(int), self.class_ids)
            return float(rows[keep, 4].max()) if keep.any() else 0.0

        # (1, 4 + num_classes [+ extras], candidates): box rows first, then one score row per class
        scores = output[0, 4:4 + len(self.names), :]
        return float(scores[self.class_ids].max())
