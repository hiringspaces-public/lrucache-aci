FROM codercom/code-server:4.89.1

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl maven ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Java 21
RUN wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg && \
    echo "deb https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" \
      > /etc/apt/sources.list.d/adoptium.list && \
    apt-get update && apt-get install -y --no-install-recommends temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/temurin-21-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

ARG REPO_URL=https://github.com/hiringspaces-public/lrucache-aci.git
ARG REPO_BRANCH=main

RUN git clone --depth=1 --branch ${REPO_BRANCH} ${REPO_URL} /home/coder/workspace && \
    chown -R coder:coder /home/coder/workspace

RUN cd /home/coder/workspace && \
    mvn dependency:resolve -f ./Java/pom.xml -q

USER coder
RUN code-server \
    --install-extension redhat.java \
    --install-extension hediet.vscode-drawio \
    || true

RUN mkdir -p /home/coder/.config/code-server
COPY --chown=coder:coder config.yaml /home/coder/.config/code-server/config.yaml
COPY --chown=coder:coder workspace.code-workspace /home/coder/workspace/lrucache.code-workspace
COPY --chown=coder:coder scripts/start.sh /usr/local/bin/start.sh

USER root
RUN chmod +x /usr/local/bin/start.sh
USER coder

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/start.sh"]