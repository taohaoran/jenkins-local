FROM jenkins/inbound-agent:latest

USER root

# sdkman 管理 JDK + Maven 多版本
RUN apt-get update && apt-get install -y curl zip unzip && \
    curl -s "https://get.sdkman.io" | bash && \
    bash -c "source \$HOME/.sdkman/bin/sdkman-init.sh && \
             sdk install java 21.0.5-tem && \
             sdk install java 17.0.12-tem && \
             sdk install java 11.0.24-tem && \
             sdk install maven 3.9.9" && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
