# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.4
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    RAILS_LOG_TO_STDOUT=1 \
    PORT=8080 \
    AWS_REGION=us-west-2 \
    AWS_LWA_READINESS_CHECK_PATH=/up \
    SECRET_KEY_BASE_PARAMETER=/portfolio/secret_key_base \
    TMPDIR=/tmp

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf /root/.bundle "${BUNDLE_PATH}"/ruby/*/cache

COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

FROM base

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 \
    /lambda-adapter /opt/extensions/lambda-adapter
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails

USER rails

EXPOSE 8080
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
