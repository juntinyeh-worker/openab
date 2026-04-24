# --- Build stage ---
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder
RUN dnf install -y gcc gcc-c++ make openssl-devel && dnf clean all
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:$PATH"
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && cargo build --release && rm -rf src
COPY src/ src/
RUN touch src/main.rs && cargo build --release

# --- Runtime stage ---
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf install -y ca-certificates curl procps ripgrep unzip shadow-utils tini && dnf clean all

# Install kiro-cli (auto-detect arch)
ARG KIRO_CLI_VERSION=2.0.0
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then URL="https://prod.download.cli.kiro.dev/stable/${KIRO_CLI_VERSION}/kirocli-aarch64-linux.zip"; \
    else URL="https://prod.download.cli.kiro.dev/stable/${KIRO_CLI_VERSION}/kirocli-x86_64-linux.zip"; fi && \
    curl --proto '=https' --tlsv1.2 -sSf --retry 3 --retry-delay 5 "$URL" -o /tmp/kirocli.zip && \
    unzip /tmp/kirocli.zip -d /tmp && \
    cp /tmp/kirocli/bin/* /usr/local/bin/ && \
    chmod +x /usr/local/bin/kiro-cli* && \
    rm -rf /tmp/kirocli /tmp/kirocli.zip

# Install gh CLI
RUN dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && \
    dnf install -y gh && dnf clean all

RUN useradd -m -s /bin/bash -u 1000 agent
RUN mkdir -p /home/agent/.local/share/kiro-cli /home/agent/.kiro && \
    chown -R agent:agent /home/agent
ENV HOME=/home/agent
WORKDIR /home/agent

COPY --from=builder --chown=agent:agent /build/target/release/openab /usr/local/bin/openab

USER agent
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD pgrep -x openab || exit 1
ENTRYPOINT ["tini", "--"]
CMD ["openab", "run", "/etc/openab/config.toml"]
