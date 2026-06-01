FROM codercom/code-server:4.89.1

# Switch to root to install system packages
USER root

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git unzip zip gnupg2 ca-certificates \
    apt-transport-https software-properties-common \
    maven gradle \
    && rm -rf /var/lib/apt/lists/*

# ── Java 21 (Temurin) ─────────────────────────────────────────────────────────
RUN wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | \
    gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg && \
    echo "deb https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" \
    > /etc/apt/sources.list.d/adoptium.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/temurin-21-amd64

# ── Pre-warm NuGet & Maven caches (speeds up first build inside session) ──────
# Clone the repo during build so the image already has the code
ARG REPO_URL=https://github.com/hiringspaces-public/lrucache-aci.git
ARG REPO_BRANCH=main

RUN git clone --depth=1 --branch ${REPO_BRANCH} ${REPO_URL} /home/coder/workspace && \
    chown -R coder:coder /home/coder/workspace

RUN cd /home/coder/workspace && \
    echo "=== Top Level ===" && \
    ls -la && \
    echo "=== lrucache ===" && \
    ls -la lrucache || true && \
    echo "=== SLN Files ===" && \
    find . -name "*.sln"

RUN export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) && \
    cd /home/coder/workspace && \
    dotnet restore ./DotNet/LruCache.sln && \
    mvn dependency:resolve -f ./Java/pom.xml -q

# ── VS Code extensions (installed at image build time) ────────────────────────
USER coder

RUN code-server --install-extension vscjava.vscode-java-pack \
                --install-extension ms-dotnettools.csharp \
                --install-extension ms-dotnettools.csdevkit \
                --install-extension eamodio.gitlens \
                --install-extension hediet.vscode-drawio \
                --install-extension streetsidesoftware.code-spell-checker \
    || true   # non-zero exit is ok if marketplace is unreachable at build time

# ── code-server config ────────────────────────────────────────────────────────
RUN mkdir -p /home/coder/.config/code-server
COPY --chown=coder:coder config.yaml /home/coder/.config/code-server/config.yaml

# ── VS Code workspace settings ────────────────────────────────────────────────
COPY --chown=coder:coder workspace.code-workspace /home/coder/workspace/lrucache.code-workspace

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY --chown=coder:coder scripts/start.sh /usr/local/bin/start.sh

USER root
RUN chmod +x /usr/local/bin/start.sh

USER coder
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/start.sh"]