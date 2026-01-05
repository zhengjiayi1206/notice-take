from notice_take.app import app
from notice_take.config import get_environment, get_server_config


if __name__ == "__main__":
    import uvicorn

    env = get_environment()
    server_cfg = get_server_config(env)
    uvicorn.run("notice_take.app:app", **server_cfg)
