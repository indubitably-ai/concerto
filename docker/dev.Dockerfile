FROM hexpm/elixir:1.19.5-erlang-28.4-debian-bookworm-20251110-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  docker.io \
  git \
  python3 \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
