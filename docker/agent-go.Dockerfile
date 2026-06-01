FROM jenkins/inbound-agent:latest

USER root

# 多 Go 版本并存，通过 symlink 切换
ENV GO_VERSIONS="1.21.13 1.22.10 1.23.4 1.24.0"

RUN for v in $GO_VERSIONS; do \
        curl -fsSL https://go.dev/dl/go${v}.linux-amd64.tar.gz | tar xz -C /usr/local && \
        mv /usr/local/go /usr/local/go${v}; \
    done && \
    ln -s /usr/local/go1.23.4 /usr/local/go

# 系统级 PATH，所有用户生效
ENV PATH=/usr/local/go/bin:$PATH

USER jenkins
