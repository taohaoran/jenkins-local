FROM jenkins/inbound-agent:latest

USER root

# uv 装到系统路径，所有用户可见
RUN apt-get update && apt-get install -y curl && \
    curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh && \
    /usr/local/bin/uv python install 3.10 3.11 3.12 3.13 && \
    /usr/local/bin/uv tool install ruff && \
    /usr/local/bin/uv tool install pytest && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
