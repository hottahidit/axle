from fastapi import FastAPI
from main import router
application = FastAPI()
application.include_router(router)
