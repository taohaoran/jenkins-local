pipeline {
    agent { label 'built-in' }

    parameters {
        string(name: 'PROJECT_DIR', defaultValue: '.',
               description: '项目子目录（如 demos/java-springboot）')
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
                                sh 'cp -r *.py pyproject.toml dist/ 2>/dev/null || true'
                                sh 'cp -r requirements.txt dist/ 2>/dev/null || true'
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
                        sh "docker tag ${tag} ${params.DOCKER_REGISTRY}/${env.APP_NAME}:latest"
                        sh "docker push ${params.DOCKER_REGISTRY}/${env.APP_NAME}:latest"
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
//  Java / SpringBoot  — 直接使用宿主 mvn + JDK
// ═══════════════════════════════════════════════════════════════════════════

def buildJava() {
    sh """
        mvn clean package \
            ${params.MAVEN_OPTS} \
            --batch-mode
    """
}

def testJava() {
    sh 'mvn test --batch-mode || true'
}

// ═══════════════════════════════════════════════════════════════════════════
//  Python / FastAPI  — uv 或 pip
// ═══════════════════════════════════════════════════════════════════════════

def buildPython() {
    if (params.PYTHON_PKG_MGR == 'uv') {
        sh 'uv sync --frozen 2>/dev/null || uv sync'
    } else {
        sh 'pip install -r requirements.txt'
    }
}

def testPython() {
    if (params.PYTHON_PKG_MGR == 'uv') {
        sh 'uv run pytest --tb=short --maxfail=5 || true'
        sh 'uv run ruff check . || true'
    } else {
        sh 'pip install pytest && pytest --tb=short --maxfail=5 || true'
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Go / Gin  — go build + go test
// ═══════════════════════════════════════════════════════════════════════════

def buildGo() {
    withEnv(["PATH+GO=/usr/local/go/bin"]) {
        sh 'go env -w GOPROXY=https://goproxy.cn,direct || true'
        sh 'go mod download'
        sh """
            CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
            go build ${params.GO_BUILD_FLAGS} -o "${env.APP_NAME}" .
        """
    }
}

def testGo() {
    withEnv(["PATH+GO=/usr/local/go/bin"]) {
        sh 'go test ./... -count=1 -timeout 120s --short || true'
    }
}
