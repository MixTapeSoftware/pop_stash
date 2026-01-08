# Build arguments
ARG ELIXIR_VERSION=1.19.2
ARG OTP_VERSION=27.3.2
ARG DEBIAN_VERSION=bookworm-20251229

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}-slim"

# Build stage
FROM ${BUILDER_IMAGE} AS build

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Copy dependency files first for better caching
COPY mix.exs mix.lock ./
COPY config config

# Install and compile dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY lib lib
COPY priv priv

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE} AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Create non-root user
RUN groupadd -r popstash && useradd -r -g popstash popstash

# Copy release from build stage
COPY --from=build --chown=popstash:popstash /app/_build/prod/rel/pop_stash ./

# Create cache directory for embedding model downloads
RUN mkdir -p /app/.cache/bumblebee && chown -R popstash:popstash /app/.cache

USER popstash

# Expose MCP port
EXPOSE 4001

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -q --spider http://localhost:4001/ || exit 1

CMD ["bin/pop_stash", "start"]
