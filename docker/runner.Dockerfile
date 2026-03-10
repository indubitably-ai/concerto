# syntax=docker/dockerfile:1.7

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  jq \
  python3 \
  ripgrep \
  zsh \
  && rm -rf /var/lib/apt/lists/*

COPY --from=codex_bin ./codex /usr/local/bin/codex

RUN chmod +x /usr/local/bin/codex \
  && codex --version >/dev/null

ENV CODEX_UNSAFE_ALLOW_NO_SANDBOX=1

CMD ["codex", "app-server"]
