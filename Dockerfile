# Use Elixir and Erlang base image
FROM elixir:1.16-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Set environment
ENV MIX_ENV=prod
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy the rest of the app (including assets)
COPY lib lib
COPY priv priv
COPY assets assets

# Build assets with esbuild

# Build release
RUN mix compile
RUN mix assets.deploy
RUN mix release

# Final minimal image
FROM alpine:3.19 AS app

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs libstdc++ bash

WORKDIR /app
ENV MIX_ENV=prod
ENV SHELL=/bin/bash

# Copy release from build stage
COPY --from=build /app/_build/prod/rel/* ./

# Start command
CMD ["bin/photoguessr", "start"]

