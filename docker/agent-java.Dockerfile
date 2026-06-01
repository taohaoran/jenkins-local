FROM jenkins/inbound-agent:latest

USER root

# 先装系统依赖
RUN apt-get update && apt-get install -y curl zip unzip && \
    rm -rf /var/lib/apt/lists/*

# sdkman 安装到 jenkins 用户目录
USER jenkins
RUN curl -s "https://get.sdkman.io" | bash && \
    bash -c ". \$HOME/.sdkman/bin/sdkman-init.sh && \
             sdk install java 21.0.5-tem && \
             sdk install java 17.0.12-tem && \
             sdk install java 11.0.24-tem && \
             sdk install maven 3.9.9"

USER jenkins
