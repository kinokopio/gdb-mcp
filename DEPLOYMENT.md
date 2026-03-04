# GDB MCP Server 部署指南

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                      ThreatScope Backend                        │
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │  Ghidra Agent   │────▶│  GDB MCP Server │                   │
│  │  (AI Analysis)  │     │  (HTTP/SSE)     │                   │
│  └─────────────────┘     └────────┬────────┘                   │
│                                   │                             │
└───────────────────────────────────┼─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GDB MCP Docker Container                     │
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │  gdb-mcp-server │────▶│      GDB        │                   │
│  │  (Port 8081)    │     │                 │                   │
│  └─────────────────┘     └────────┬────────┘                   │
│                                   │                             │
│                          ┌────────▼────────┐                   │
│                          │   gdbserver     │                   │
│                          │   (调试目标)     │                   │
│                          └─────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 方式一：Docker 部署（推荐）

### 1. 构建镜像

```bash
cd /path/to/threatscope-gdb-mcp
docker build -t threatscope/gdb-mcp:latest .
```

### 2. 运行容器

```bash
# 基础运行
docker run -d \
  --name gdb-mcp-server \
  -p 8081:8081 \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  threatscope/gdb-mcp:latest

# 带样本目录挂载
docker run -d \
  --name gdb-mcp-server \
  -p 8081:8081 \
  -v /path/to/samples:/samples:ro \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  threatscope/gdb-mcp:latest
```

### 3. 使用 docker-compose

```bash
cd /path/to/threatscope-gdb-mcp
docker-compose up -d
```

### 4. 验证服务

```bash
# 检查容器状态
docker ps | grep gdb-mcp

# 检查日志
docker logs gdb-mcp-server

# 测试 SSE 端点
curl -N http://localhost:8081/sse
```

---

## 方式二：直接安装

### 1. 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y gdb gdbserver python3.11 python3-pip

# CentOS/RHEL
sudo yum install -y gdb gdb-gdbserver python3.11 python3-pip
```

### 2. 安装 gdb-mcp-server

```bash
cd /path/to/threatscope-gdb-mcp

# 使用 pip
pip install .

# 或使用 pipx（推荐，隔离环境）
pipx install .
```

### 3. 运行服务

```bash
# stdio 模式（本地子进程）
gdb-mcp-server --mode stdio

# SSE/HTTP 模式（远程服务）
gdb-mcp-server --mode sse --host 0.0.0.0 --port 8081
```

### 4. Systemd 服务（生产环境）

创建 `/etc/systemd/system/gdb-mcp.service`:

```ini
[Unit]
Description=GDB MCP Server
After=network.target

[Service]
Type=simple
User=threatscope
ExecStart=/usr/local/bin/gdb-mcp-server --mode sse --host 0.0.0.0 --port 8081
Restart=always
RestartSec=5
Environment=GDB_PATH=/usr/bin/gdb
Environment=GDB_MCP_LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
```

启用服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable gdb-mcp
sudo systemctl start gdb-mcp
sudo systemctl status gdb-mcp
```

---

## ThreatScope 配置

### 环境变量

```bash
# .env 文件
THREATSCOPE_GDB_ENABLED=true
THREATSCOPE_GDB_SERVICE_MODE=http
THREATSCOPE_GDB_MCP_URL=http://localhost:8081
THREATSCOPE_GDB_TIMEOUT=300
```

### 配置说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `THREATSCOPE_GDB_ENABLED` | `false` | 启用 GDB 动态分析 |
| `THREATSCOPE_GDB_SERVICE_MODE` | `stdio` | `stdio` (本地) 或 `http` (Docker) |
| `THREATSCOPE_GDB_MCP_URL` | `http://localhost:8081` | HTTP 模式下的服务地址 |
| `THREATSCOPE_GDB_MCP_COMMAND` | `["gdb-mcp-server"]` | stdio 模式下的启动命令 |
| `THREATSCOPE_GDB_GDB_PATH` | `gdb` | GDB 可执行文件路径 |
| `THREATSCOPE_GDB_TIMEOUT` | `300` | 分析超时时间（秒） |

---

## 使用示例

### Python API 调用

```python
from src.threatscope.analysis.agents.ghidra_agent import GhidraAgent
from src.threatscope.analysis.agents.base import AgentConfig

# 创建配置
config = AgentConfig(
    system_prompt_path='prompts/ghidra_agent.md',
    max_iterations=20
)

# 创建 Agent（启用 GDB）
agent = GhidraAgent(
    config=config,
    ghidra_url="http://localhost:8000",
    enable_gdb=True,
)

# 运行分析
context = {
    "static_results": {...},
    "file_path": "/samples/malware.elf",
    "sample_hash": "abc123...",
}

result = await agent.analyze(context)
```

### AI Agent 工具调用示例

AI 可以自由组合使用 Ghidra（静态）和 GDB（动态）工具：

```
# 1. 静态分析 - 找到可疑函数
mcp__ghidra__list_functions()
mcp__ghidra__decompile_function(target="decrypt_config")

# 2. 动态分析 - 启动 GDB 会话
mcp__gdb__gdb_start_session(program="/samples/malware.elf")

# 3. 设置断点
mcp__gdb__gdb_set_breakpoint(location="decrypt_config")

# 4. 运行到断点
mcp__gdb__gdb_execute_command(command="run")

# 5. 检查运行时数据
mcp__gdb__gdb_get_variables()
mcp__gdb__gdb_read_memory(address="$rdi", size=256, format="string")

# 6. 提取解密后的 C2 地址
# AI 发现: "192.168.1.100:4444"

# 7. 清理
mcp__gdb__gdb_stop_session()
```

---

## 可用工具列表（26 个）

### 会话管理
| 工具 | 说明 |
|------|------|
| `gdb_start_session` | 启动 GDB 会话 |
| `gdb_execute_command` | 执行任意 GDB 命令 |
| `gdb_call_function` | 调用目标进程函数 |
| `gdb_get_status` | 获取会话状态 |
| `gdb_stop_session` | 停止会话 |

### 线程/帧导航
| 工具 | 说明 |
|------|------|
| `gdb_get_threads` | 获取所有线程 |
| `gdb_select_thread` | 选择线程 |
| `gdb_get_backtrace` | 获取调用栈 |
| `gdb_select_frame` | 选择栈帧 |
| `gdb_get_frame_info` | 获取帧信息 |

### 断点管理
| 工具 | 说明 |
|------|------|
| `gdb_set_breakpoint` | 设置断点（支持条件） |
| `gdb_list_breakpoints` | 列出所有断点 |
| `gdb_delete_breakpoint` | 删除断点 |
| `gdb_enable_breakpoint` | 启用断点 |
| `gdb_disable_breakpoint` | 禁用断点 |

### 执行控制
| 工具 | 说明 |
|------|------|
| `gdb_continue` | 继续执行 |
| `gdb_step` | 单步进入 |
| `gdb_next` | 单步跳过 |
| `gdb_interrupt` | 中断执行（暂停死循环） |

### 数据检查
| 工具 | 说明 |
|------|------|
| `gdb_evaluate_expression` | 求值 C 表达式 |
| `gdb_get_variables` | 获取局部变量 |
| `gdb_get_registers` | 获取寄存器 |

### 内存操作（扩展）
| 工具 | 说明 |
|------|------|
| `gdb_read_memory` | 读取内存（hex/bytes/string） |
| `gdb_write_memory` | 写入内存（patch 反调试） |
| `gdb_disassemble` | 反汇编指令 |
| `gdb_set_watchpoint` | 设置内存监视点 |

---

## 安全注意事项

### Docker 权限

GDB 需要 `SYS_PTRACE` 权限才能调试进程：

```bash
docker run --cap-add=SYS_PTRACE --security-opt seccomp=unconfined ...
```

### 网络隔离

分析恶意软件时，建议隔离网络：

```bash
docker run --network none ...
```

### 资源限制

```bash
docker run \
  --memory=4g \
  --cpus=2 \
  --pids-limit=100 \
  ...
```

---

## 故障排除

### 1. 连接失败

```bash
# 检查服务是否运行
curl http://localhost:8081/sse

# 检查端口
netstat -tlnp | grep 8081

# 检查日志
docker logs gdb-mcp-server
```

### 2. GDB 权限错误

```
ptrace: Operation not permitted
```

解决：添加 `--cap-add=SYS_PTRACE --security-opt seccomp=unconfined`

### 3. 超时

```bash
# 增加超时时间
export THREATSCOPE_GDB_TIMEOUT=600
```

### 4. 内存不足

```bash
# 增加容器内存
docker run --memory=8g ...
```

---

## 日志级别

```bash
# 调试模式
export GDB_MCP_LOG_LEVEL=DEBUG
gdb-mcp-server --mode sse

# 生产模式
export GDB_MCP_LOG_LEVEL=INFO
```
