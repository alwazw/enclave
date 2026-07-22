FROM python:3.12-slim

WORKDIR /app
RUN pip install --no-cache-dir langgraph openai httpx typing-extensions

COPY graph.py .

ENV WORKSPACE=/workspace
CMD ["python", "graph.py", "--help"]
