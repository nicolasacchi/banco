# syntax=docker/dockerfile:1
# check=error=true

# Production image. Build: docker build -t banco:dev .
# .ruby-version is the single source of the Ruby version; test/lib/toolchain_test.rb
# checks that this ARG matches it.
ARG RUBY_VERSION=3.4.10
ARG NODE_VERSION=26.7.0

# Node binary for the expression grader worker only (no npm, no Chrome here).
FROM docker.io/library/node:${NODE_VERSION}-slim AS node

FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# sqlite3 CLI: without it db:prepare truncates db/structure.sql to 0 bytes.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libatomic1 libjemalloc2 libstdc++6 sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    SOLID_QUEUE_IN_PUMA="1" \
    RAILS_MAX_THREADS="5" \
    WEB_PORT="3000" \
    API_PORT="3100" \
    HARNESS_PORT="3200" \
    BANCO_DATA_DIR="/data/db"

# Throw-away build stage
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock .ruby-version ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompile assets without a real secret.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final image
FROM base

# Recorded in every grading (grader_version); the image has no .git.
ARG GIT_SHA=unknown
ENV BANCO_GIT_SHA=${GIT_SHA}

# Numeric user; set APP_UID to the owner of the data directory (data/banco).
ARG APP_UID=1000
ARG APP_GID=1000
RUN groupadd --system --gid ${APP_GID} banco && \
    useradd banco --uid ${APP_UID} --gid ${APP_GID} --create-home --shell /bin/bash && \
    mkdir -p /data/db && chown ${APP_UID}:${APP_GID} /data /data/db

COPY --from=node /usr/local/bin/node /usr/local/bin/node
# Fail the build if the copied binary cannot run (missing shared libraries).
RUN node --version

COPY --chown=${APP_UID}:${APP_GID} --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=${APP_UID}:${APP_GID} --from=build /rails /rails
RUN mkdir -p /rails/tmp /rails/log /rails/storage && chown -R ${APP_UID}:${APP_GID} /rails/tmp /rails/log /rails/storage

USER ${APP_UID}:${APP_GID}

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000 3100 3200
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:3000/up || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
