FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# CPU torch first, then pin it. A later pip install otherwise replaces it
# with the CUDA wheel, which this VPS cannot run. mlx-lm is Mac-only.
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
    && python -c "import torch; open('/tmp/constraint.txt','w').write('torch=='+torch.__version__+'\n')" \
    && grep -v -i 'mlx' requirements.txt > /tmp/requirements.txt \
    && pip install --no-cache-dir -c /tmp/constraint.txt -r /tmp/requirements.txt \
    && python -c "import torch; assert '+cpu' in torch.__version__, torch.__version__"

COPY . .

ENV HF_HUB_DISABLE_XET=1 \
    HF_HUB_OFFLINE=0 \
    COPILOT_BACKEND=extractive \
    PYTHONUNBUFFERED=1

RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('BAAI/bge-m3', local_dir='models/bge-m3')" \
    && touch models/bge-m3/.fetched \
    && HF_HUB_OFFLINE=1 python ingest.py

ENV HF_HUB_OFFLINE=1

EXPOSE 8000

# server.py binds 127.0.0.1, which Traefik cannot reach.
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
