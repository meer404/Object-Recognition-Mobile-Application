# Reproducible YOLO export environment.
#
# Ultralytics 8.4.198 refuses LiteRT export on Windows ("LiteRT export only
# supported on Linux x86 and macOS") and Core ML export on Windows, so exports
# run in this Linux image. See docs/decisions.md D-012.
#
# Build (from repo root):
#   docker build -f tools/docker/export.Dockerfile -t kurdish-vision-export .
# Run: see tools/README.md
FROM python:3.11.9-slim-bookworm

# OpenCV (pulled in by ultralytics) needs these shared libraries.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu \
      torch==2.14.1 torchvision==0.29.1

COPY tools/requirements-export.txt /tmp/requirements-export.txt
RUN pip install --no-cache-dir -r /tmp/requirements-export.txt \
 && pip freeze > /opt/requirements-export.lock.txt

# Ultralytics settings live in the image (read once at import, so they must
# be set before the export script runs). No analytics.
ENV YOLO_CONFIG_DIR=/opt/ultralytics-config \
    PYTHONDONTWRITEBYTECODE=1
RUN yolo settings sync=False datasets_dir=/opt/datasets weights_dir=/opt/weights runs_dir=/tmp/runs

# Bake inputs into the image so every run uses byte-identical weights and
# calibration data, read from local disk (bind mounts are slow, and LiteRT
# cannot memory-map files on Docker Desktop's Windows mounts).
RUN mkdir -p /opt/weights && cd /opt/weights \
 && python -c "from ultralytics import YOLO; YOLO('yolo26n.pt')" \
 && python -c "from ultralytics.data.utils import check_det_dataset; check_det_dataset('coco128.yaml')" \
 && sha256sum /opt/weights/yolo26n.pt

WORKDIR /work
ENTRYPOINT ["python", "tools/export_model.py"]
CMD ["--weights", "/opt/weights/yolo26n.pt"]
