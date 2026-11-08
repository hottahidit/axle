from fastapi import FastAPI

def create_app(data_dir=None):
    app = FastAPI(title="x")
    return app
