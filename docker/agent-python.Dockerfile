FROM jenkins/inbound-agent:latest

USER root

# uv 自带 Python 版本管理，pip 作为 fallback
RUN apt-get update && apt-get install -y curl && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    /root/.local/bin/uv python install 3.10 3.11 3.12 3.13 && \
    /root/.local/bin/uv tool install ruff && \
    /root/.local/bin/uv tool install pytest && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
