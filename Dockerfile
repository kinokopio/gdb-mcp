FROM python:3.11-slim

LABEL maintainer="ThreatScope"
LABEL description="GDB MCP Server for AI-driven dynamic analysis"

RUN apt-get update && apt-get install -y --no-install-recommends \
    gdb \
    gdbserver \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml .
COPY src/ src/

RUN pip install --no-cache-dir .

ENV GDB_PATH=/usr/bin/gdb
ENV GDB_MCP_LOG_LEVEL=INFO
ENV GDB_MCP_MODE=sse
ENV GDB_MCP_HOST=0.0.0.0
ENV GDB_MCP_PORT=8081

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8081/health || exit 1

ENTRYPOINT ["gdb-mcp-server", "--mode", "sse"]
