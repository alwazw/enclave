FROM python:3.12-slim

# git = the board's audit trail; curl = compose healthcheck
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY board.py app.py main.py ./

ENV BOARD_DIR=/board
EXPOSE 8090

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8090"]
