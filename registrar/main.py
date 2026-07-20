"""Service entrypoint: uvicorn main:app"""
from app import create_app

app = create_app()
