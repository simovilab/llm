import os

import httpx
from fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import PlainTextResponse

LITELLM_BASE_URL = os.environ.get("LITELLM_BASE_URL", "http://litellm:4000")
LITELLM_API_KEY = os.environ.get("LITELLM_API_KEY", "")

mcp = FastMCP("llm-server")


@mcp.custom_route("/health", methods=["GET"])
async def health(request: Request) -> PlainTextResponse:
    return PlainTextResponse("OK")


@mcp.tool
def ping() -> str:
    """Check that the MCP server is reachable."""
    return "pong"


@mcp.tool
async def list_llm_models() -> list[str]:
    """List the models available through the LiteLLM gateway."""
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.get(
            f"{LITELLM_BASE_URL}/v1/models",
            headers={"Authorization": f"Bearer {LITELLM_API_KEY}"},
        )
        response.raise_for_status()
        return [model["id"] for model in response.json()["data"]]


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
