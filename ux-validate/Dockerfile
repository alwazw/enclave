FROM mcr.microsoft.com/playwright/python:v1.47.0-jammy

WORKDIR /app
RUN pip install --no-cache-dir fastapi "uvicorn[standard]" httpx playwright==1.47.0

COPY app.py .

ENV BOARD_DIR=/board
EXPOSE 8091

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8091"]
