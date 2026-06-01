pipeline {
    agent { label 'built-in' }

    environment {
        // Docker daemon 通过 socat 代理访问宿主
        DOCKER_HOST = 'tcp://alpine:2375'
        // 容器内 JENKINS_HOME 对应的宿主路径（经 /home 挂载点）
        HOST_JENKINS_HOME = '/home/volume/local_jenkins/jenkins_home'
    }

    parameters {
        string(name: 'PROJECT_DIR', defaultValue: '.',
               description: '项目子目录（如 demos/java-springboot），留空为仓库根目录')
        choice(name: 'JDK_VERSION', choices: ['jdk21', 'jdk17', 'jdk11'],
               description: 'JDK 版本（Java 项目）')
        choice(name: 'PYTHON_VERSION', choices: ['3.13', '3.12', '3.11', '3.10'],
               description: 'Python 版本（Python 项目）')
        choice(name: 'GO_VERSION', choices: ['1.24', '1.23', '1.22', '1.21'],
               description: 'Go 版本（Go 项目）')
        choice(name: 'PYTHON_PKG_MGR', choices: ['uv', 'pip'],
               description: 'Python 依赖管理工具')
        string(name: 'MAVEN_OPTS', defaultValue: '-DskipTests',
               description: 'mvn 额外参数')
        string(name: 'GO_BUILD_FLAGS', defaultValue: '-ldflags="-s -w"',
               description: 'go build 额外参数')
        booleanParam(name: 'BUILD_DOCKER_IMAGE', defaultValue: false,
                     description: '是否构建 Docker 镜像')
        string(name: 'DOCKER_REGISTRY', defaultValue: '',
               description: 'Docker Registry 地址')
    }

    stages {
        stage('Detect Project Type') {
            steps {
                script {
                    dir(params.PROJECT_DIR) {
                        if (fileExists('pom.xml')) {
                            env.PROJECT_TYPE = 'java-springboot'
                        } else if (fileExists('pyproject.toml') || fileExists('requirements.txt')) {
                            env.PROJECT_TYPE = 'python-fastapi'
                        } else if (fileExists('go.mod')) {
                            env.PROJECT_TYPE = 'go-gin'
                        } else {
                            error("无法识别项目类型：${params.PROJECT_DIR} 下未找到 pom.xml / pyproject.toml / go.mod")
                        }
                        env.APP_NAME = sh(script: 'basename "$(pwd)"', returnStdout: true).trim()
                    }
                    echo "项目目录: ${params.PROJECT_DIR}"
                    echo "检测到项目类型: ${env.PROJECT_TYPE}"
                    echo "应用名称: ${env.APP_NAME}"
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    dir(params.PROJECT_DIR) {
                        switch (env.PROJECT_TYPE) {
                            case 'java-springboot': buildJava(); break
                            case 'python-fastapi':  buildPython(); break
                            case 'go-gin':          buildGo(); break
                        }
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    dir(params.PROJECT_DIR) {
                        switch (env.PROJECT_TYPE) {
                            case 'java-springboot': testJava(); break
                            case 'python-fastapi':  testPython(); break
                            case 'go-gin':          testGo(); break
                        }
                    }
                }
            }
        }

        stage('Collect Artifacts') {
            steps {
                script {
                    dir(params.PROJECT_DIR) {
                        sh 'mkdir -p dist'
                        switch (env.PROJECT_TYPE) {
                            case 'java-springboot':
                                sh 'cp target/*.jar dist/ || true'
                                break
                            case 'python-fastapi':
                                sh """
                                    rsync -a --exclude='__pycache__' --exclude='.venv' \
                                        --exclude='.git' --exclude='dist' . dist/
                                """
                                break
                            case 'go-gin':
                                sh "cp ${env.APP_NAME} dist/ || true"
                                break
                        }
                        archiveArtifacts artifacts: 'dist/**', fingerprint: true
                    }
                }
            }
        }

        stage('Docker Build & Push') {
            when { expression { params.BUILD_DOCKER_IMAGE } }
            steps {
                script {
                    def tag = params.DOCKER_REGISTRY
                        ? "${params.DOCKER_REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                        : "${env.APP_NAME}:${env.BUILD_NUMBER}"
                    sh "docker build -t ${tag} -f ${params.PROJECT_DIR}/docker/Dockerfile ${params.PROJECT_DIR}"
                    if (params.DOCKER_REGISTRY) {
                        sh "docker push ${tag}"
                        sh """
                            docker tag ${tag} ${params.DOCKER_REGISTRY}/${env.APP_NAME}:latest
                            docker push ${params.DOCKER_REGISTRY}/${env.APP_NAME}:latest
                        """
                    }
                }
            }
        }
    }

    post {
        success { echo "构建成功: ${env.APP_NAME} (${env.PROJECT_TYPE})" }
        failure { echo "构建失败: ${env.APP_NAME} (${env.PROJECT_TYPE})" }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  将容器内 workspace 路径转为宿主可访问路径
//  /var/jenkins_home → /home/volume/local_jenkins/jenkins_home
// ═══════════════════════════════════════════════════════════════════════════

def hostPath(containerPath) {
    return containerPath.replace('/var/jenkins_home', env.HOST_JENKINS_HOME)
}

def workdirHost() {
    return hostPath(sh(script: 'pwd', returnStdout: true).trim())
}

// ═══════════════════════════════════════════════════════════════════════════
//  Java / SpringBoot
// ═══════════════════════════════════════════════════════════════════════════

def buildJava() {
    def jdkTag = params.JDK_VERSION.replace('jdk', '')
    def wd = workdirHost()
    sh """
        docker run --rm \
            -v ${wd}:/workspace -w /workspace \
            -v ${env.HOST_JENKINS_HOME}/.m2:/root/.m2 \
            maven:3.9-eclipse-temurin-${jdkTag} \
            mvn clean package ${params.MAVEN_OPTS} \
                -Dmaven.repo.local=/root/.m2/repository \
                --batch-mode
    """
}

def testJava() {
    def jdkTag = params.JDK_VERSION.replace('jdk', '')
    def wd = workdirHost()
    sh """
        docker run --rm \
            -v ${wd}:/workspace -w /workspace \
            -v ${env.HOST_JENKINS_HOME}/.m2:/root/.m2 \
            maven:3.9-eclipse-temurin-${jdkTag} \
            mvn test -Dmaven.repo.local=/root/.m2/repository --batch-mode || true
    """
}

// ═══════════════════════════════════════════════════════════════════════════
//  Python / FastAPI
// ═══════════════════════════════════════════════════════════════════════════

def buildPython() {
    def wd = workdirHost()
    if (params.PYTHON_PKG_MGR == 'uv') {
        sh """
            docker run --rm \
                -v ${wd}:/workspace -w /workspace \
                ghcr.io/astral-sh/uv:python${params.PYTHON_VERSION}-bookworm \
                sh -c 'uv sync --frozen 2>/dev/null || uv sync'
        """
    } else {
        sh """
            docker run --rm \
                -v ${wd}:/workspace -w /workspace \
                -v ${env.HOST_JENKINS_HOME}/.cache/pip:/root/.cache/pip \
                python:${params.PYTHON_VERSION}-slim \
                sh -c 'pip install --upgrade pip && pip install -r requirements.txt'
        """
    }
}

def testPython() {
    def wd = workdirHost()
    if (params.PYTHON_PKG_MGR == 'uv') {
        sh """
            docker run --rm \
                -v ${wd}:/workspace -w /workspace \
                ghcr.io/astral-sh/uv:python${params.PYTHON_VERSION}-bookworm \
                sh -c 'uv run pytest --tb=short --maxfail=5 || true; uv run ruff check . || true'
        """
    } else {
        sh """
            docker run --rm \
                -v ${wd}:/workspace -w /workspace \
                python:${params.PYTHON_VERSION}-slim \
                sh -c 'pip install pytest && pytest --tb=short --maxfail=5 || true'
        """
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Go / Gin
// ═══════════════════════════════════════════════════════════════════════════

def buildGo() {
    def wd = workdirHost()
    sh """
        docker run --rm \
            -v ${wd}:/workspace -w /workspace \
            -v ${env.HOST_JENKINS_HOME}/go/pkg/mod:/go/pkg/mod \
            -e GOPATH=/go \
            golang:${params.GO_VERSION}-bookworm \
            sh -c 'go env -w GOPROXY=https://goproxy.cn,direct || true;
                   go mod download;
                   CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build ${params.GO_BUILD_FLAGS} -o "${env.APP_NAME}" .'
    """
}

def testGo() {
    def wd = workdirHost()
    sh """
        docker run --rm \
            -v ${wd}:/workspace -w /workspace \
            -v ${env.HOST_JENKINS_HOME}/go/pkg/mod:/go/pkg/mod \
            -e GOPATH=/go \
            golang:${params.GO_VERSION}-bookworm \
            go test ./... -count=1 -timeout 120s --short || true
    """
}
