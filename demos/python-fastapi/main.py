from fastapi import FastAPI

app = FastAPI(title="python-fastapi-demo")


@app.get("/hello")
async def hello(name: str = "World"):
    return {"message": f"Hello, {name}!"}
