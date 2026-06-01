# 通用后端服务 Jenkins 构建方案

## 目标

一套 Jenkins Pipeline，自动识别 Java/SpringBoot、Python/FastAPI、Go/Gin 项目类型，完成构建、测试、产物归档，支持版本参数化。

---

## 最终方案：原生工具构建（Docker-free）

### 架构

```
Jenkinsfile (仓库根目录)
├── Detect Stage ── 扫描 fileExists(pom.xml / pyproject.toml / go.mod) → 判定 PROJECT_TYPE
├── Build Stage  ── 根据类型调用 mvn / uv / go build
├── Test Stage   ── mvn test / pytest / go test
├── Collect      ── 产物归档到 dist/
└── Docker Build ── 可选，构建最终运行时镜像
```

### 项目探测

| 标记文件 | 判定类型 | 构建工具 |
|----------|----------|----------|
| `pom.xml` | java-springboot | Maven |
| `pyproject.toml` 或 `requirements.txt` | python-fastapi | uv / pip |
| `go.mod` | go-gin | Go modules |

### 参数设计

| 参数 | 作用 | 默认值 |
|------|------|--------|
| `PROJECT_DIR` | 子目录路径 | `.` |
| `JDK_VERSION` | Java 版本选择 | `jdk21` |
| `PYTHON_VERSION` | Python 版本选择 | `3.12` |
| `GO_VERSION` | Go 版本选择 | `1.23` |
| `PYTHON_PKG_MGR` | Python 包管理器 | `uv` |
| `MAVEN_OPTS` | mvn 额外参数 | `-DskipTests` |
| `GO_BUILD_FLAGS` | go build ldflags | `-ldflags="-s -w"` |
| `BUILD_DOCKER_IMAGE` | 是否构建镜像 | `false` |
| `DOCKER_REGISTRY` | Registry 地址 | 空 |

### 前置条件

Jenkins 节点需预装：

```bash
# Debian/Ubuntu
apt-get install -y maven python3 python3-pip
pip3 install uv
curl -fsSL https://go.dev/dl/go1.23.4.linux-amd64.tar.gz | tar xz -C /usr/local
```

---

## 调试过程回顾

### 问题 1：Detect 阶段找不到项目文件

**现象**：`未找到 pom.xml / pyproject.toml / go.mod`

**原因**：Jenkinsfile 在仓库根目录，但 demo 在 `demos/java-springboot/` 子目录，`fileExists('pom.xml')` 检查的是根目录。

**解决**：新增 `PROJECT_DIR` 参数，用 `dir(params.PROJECT_DIR)` 包裹探测逻辑。构建时传入 `PROJECT_DIR=demos/java-springboot`。

### 问题 2：docker.image() 在 Groovy 沙箱不可用

**现象**：`MissingPropertyException: No such property: docker`

**原因**：Declarative Pipeline 的 `def` 函数运行在 Groovy 沙箱中，`docker` 全局变量（来自 Docker Pipeline 插件）在沙箱中默认不可用。

**尝试方案 A**：Jenkins In-process Script Approval 中批准 `docker` 方法。可行但需要管理员手动操作，不通用。

**尝试方案 B**：改用 `sh 'docker run ...'` 直接调用 CLI。绕过了沙箱限制，但引入了后续的 Docker 环境问题。

### 问题 3：Agent 节点无 Docker

**现象**：`docker: not found`（agent `alpine-00004pel2wjpb`）

**原因**：`agent any` 调度到了云 agent 节点，该节点未安装 Docker。

**解决**：改为 `agent { label 'built-in' }`，锁定到 Jenkins 主节点。

### 问题 4：Docker CLI 不可执行

**现象**：`docker: Permission denied`（built-in 节点）

**原因**：Jenkins 运行在 Docker 容器中，宿主机 macOS 的 `/usr/bin/docker` 是 Mach-O 二进制，挂载进 Linux 容器后无法执行。

**解决**（Docker 路线）：下载 Linux 版 Docker CLI 到容器内，并设置 `DOCKER_HOST=tcp://alpine:2375` 指向 socat 代理。

### 问题 5：Docker-in-Docker 路径映射

**现象**：`docker run` 的 `-v` 卷挂载指向容器内路径，但 Docker daemon 在宿主机上，路径不存在。

**原因**：
```
容器内: /var/jenkins_home/workspace/foo
宿主机: $HOME/volume/local_jenkins/jenkins_home/workspace/foo
```
Docker daemon 运行在宿主机，只认宿主机路径。

**解决**：路径翻译——通过 `-v "$HOME":/home` 挂载点，将容器内 `/var/jenkins_home` 替换为 `/home/volume/local_jenkins/jenkins_home`，使 Docker daemon 能找到正确路径。

### 问题 6：Go 构建失败

**现象 1**：`go: not found` → 容器内 Go 未安装，通过 `withEnv(["PATH+GO=/usr/local/go/bin"])` 解决。

**现象 2**：`missing go.sum entry` → 项目缺少 `go.sum`，在构建步骤中添加 `go mod tidy` 自动生成。

---

## Docker 方案探讨

如果坚持用 Docker 容器做构建环境（隔离性更好、不污染节点），需要解决以下核心问题：

### 环境拓扑

```
┌─────────────────────────────────────────────┐
│  宿主机 (macOS/Linux)                        │
│  ┌──────────────────────────────────────┐   │
│  │  Jenkins 容器 (jenkins/jenkins:lts)   │   │
│  │  - 作为 Pipeline 执行节点              │   │
│  │  - DOCKER_HOST 指向宿主机 daemon       │   │
│  └──────────────┬───────────────────────┘   │
│                 │ TCP :2375 (socat)          │
│  ┌──────────────▼───────────────────────┐   │
│  │  Docker Daemon (宿主机)               │   │
│  │  - 执行 docker run maven / golang... │   │
│  │  - 需要访问 workspace 文件             │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 三种可行方案

#### 方案 A：宿主机路径映射（当前尝试的路线）

Jenkins 容器通过 volume mount 看到宿主机路径，`docker run -v` 使用宿主路径。

```
-v "$HOME"/volume/local_jenkins/jenkins_home:/var/jenkins_home  # Jenkins 数据
-v "$HOME":/home                                                 # 用于路径翻译
```

**Jenkinsfile 关键代码**：

```groovy
environment {
    DOCKER_HOST = 'tcp://alpine:2375'
    HOST_JENKINS_HOME = '/home/volume/local_jenkins/jenkins_home'
}

def hostPath(containerPath) {
    return containerPath.replace('/var/jenkins_home', env.HOST_JENKINS_HOME)
}
```

**优点**：不改变现有容器拓扑。

**缺点**：
- 路径依赖启动参数，移植性差
- macOS 上 Docker CLI 是 Mach-O 二进制，必须额外安装 Linux 版本
- `docker run` 拉取镜像可能触发 Docker Hub 限流

#### 方案 B：Docker-out-of-Docker (DooD) — 挂载 socket

Jenkins 容器直接挂载宿主机 `/var/run/docker.sock`，容器内安装 Linux 版 Docker CLI。

```
-v /var/run/docker.sock:/var/run/docker.sock
```

**优点**：不需要 TCP 代理（socat），DOCKER_HOST 用默认 socket。

**缺点**：
- **路径问题依旧**：workspace 在容器内，docker daemon 在宿主机，卷挂载路径仍需翻译
- 容器直接操作宿主机 Docker，安全风险较高（等于 root 权限）

#### 方案 C：Docker-in-Docker (DinD) — 独立 Docker Daemon

Jenkins 容器内运行一个独立的 Docker daemon（`docker:dind` sidecar）。

```yaml
services:
  jenkins:
    image: jenkins/jenkins:lts
    environment:
      DOCKER_HOST: tcp://dind:2375
  dind:
    image: docker:dind
    privileged: true
```

**优点**：构建容器和 Jenkins 共享同一个 Docker 网络，卷挂载路径自然一致。

**缺点**：
- 需要 `--privileged` 权限
- 构建容器内的文件系统与宿主机隔离，镜像缓存不能复用
- 镜像拉取每次都是全新的，耗时长

### Docker 方案选型建议

| 场景 | 推荐方案 |
|------|----------|
| 简单 CI，节点可控 | **原生工具**（当前方案）— 最简单，无路径问题 |
| 需要版本隔离，不想装多版本 JDK/Python | 方案 A + 宿主机路径映射 |
| Kubernetes / 云原生环境 | 方案 C (DinD sidecar) 或 Kaniko |
| 已有 Jenkins Docker 插件 | 使用 `docker.image().inside()` + 脚本审批 |

### 结论

对于当前场景（单机 Jenkins，节点可控），**原生工具方案最优**：

1. 零路径翻译，无 Docker-in-Docker 的复杂度
2. 构建速度快（无镜像拉取开销）
3. 依赖缓存自然持久化（`.m2`、`GOPATH`、pip cache）
4. 版本切换可通过 `sdkman` / `pyenv` / `gvm` 等工具实现，比换 Docker 镜像更轻量

如果未来迁移到 Kubernetes 或需要严格构建环境隔离，再考虑 DinD 路线。

---

## Cloud Agent 多版本方案（推荐演进方向）

### 架构

```
Jenkins Controller (built-in, 只做调度 + 轻量步骤)
  │
  ├── Agent "java-build"   ── sdkman → JDK 21/17/11 + Maven
  ├── Agent "python-build" ── uv     → Python 3.10~3.13 + pytest/ruff
  └── Agent "go-build"     ── symlink → Go 1.21~1.24
```

每个 Agent 是一个 Docker 容器（Docker plugin 动态创建），镜像预装版本管理器：

| Agent 镜像 | 版本管理 | 切换方式 |
|------------|----------|----------|
| `agent-java` | sdkman | `source sdkman-init.sh && sdk use java 21-tem` |
| `agent-python` | uv | `uv venv --python 3.12` |
| `agent-go` | ln -sf | `ln -sf /usr/local/go1.23.4 /usr/local/go` |

### Agent Dockerfile

**Java** (`docker/agent-java.Dockerfile`)：基于 `jenkins/inbound-agent`，通过 sdkman 安装 JDK 21/17/11 和 Maven。

**Python** (`docker/agent-python.Dockerfile`)：基于 `jenkins/inbound-agent`，通过 uv 管理 Python 3.10~3.13 + pytest + ruff。

**Go** (`docker/agent-go.Dockerfile`)：基于 `jenkins/inbound-agent`，多版本并存于 `/usr/local/go${ver}`，通过 symlink 激活。

### Jenkinsfile 调度逻辑

```groovy
pipeline {
    agent none                    // Controller 不参与构建

    stages {
        stage('Detect') {
            agent { label 'built-in' }  // 轻量检测用 Controller
        }
        stage('Build') {
            steps {
                script {
                    switch (env.PROJECT_TYPE) {
                        case 'java-springboot': node('java-build') { buildJava() }
                        case 'python-fastapi':  node('python-build') { buildPython() }
                        case 'go-gin':          node('go-build') { buildGo() }
                    }
                }
            }
        }
    }
}
```

### 缓存策略

| 缓存 | 方案 |
|------|------|
| `.m2` Maven 仓库 | 挂载 host volume 或使用 Nexus/Artifactory proxy |
| `GOPATH/pkg/mod` | 挂载 host volume |
| `uv/pip cache` | `$HOME/.cache/uv` 挂载 volume |

### 构建流程

1. Controller checkout 代码
2. Detect stage（built-in 节点）扫描标记文件，判定语言类型
3. Build stage — Jenkins Docker plugin 按 label 创建对应 Agent 容器
4. Agent 内执行版本切换 + 构建命令
5. Agent 使用完毕自动销毁（`DockerOnceRetentionStrategy`）
