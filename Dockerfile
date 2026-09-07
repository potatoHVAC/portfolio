# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.4
FROM ruby:${RUBY_VERSION}-slim AS build

WORKDIR /rails

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf /root/.bundle "${BUNDLE_PATH}"/ruby/*/cache

COPY app/ app/
COPY bin/rails bin/rake bin/
COPY config/application.rb config/boot.rb config/environment.rb config/media.json \
    config/portfolio.yml config/puma.rb config/routes.rb config/
COPY config/build_books/ config/build_books/
COPY config/environments/production.rb config/environments/
COPY config/initializers/ config/initializers/
COPY config/locales/ config/locales/
COPY lib/ lib/
COPY public/ public/
COPY config.ru Rakefile ./

RUN SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production bin/rails assets:precompile

# The installed application shared by test and production. Build-only packages
# and source files outside the explicit runtime set never enter this stage.
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash --no-log-init

COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /rails /rails

RUN mkdir -p log tmp/pids && chown -R rails:rails log tmp

USER rails

# Rails already provides Minitest. This stage adds only the test environment and
# suite; install future test-only dependencies here rather than in base.
FROM base AS test

ENV RAILS_ENV=test

COPY --chown=rails:rails config/environments/test.rb config/environments/test.rb
COPY --chown=rails:rails test/ test/

CMD ["bin/rails", "test"]

# Keep this last so an unqualified docker build always produces the publishable
# image. Everything above this point is shared with the tested image.
FROM base AS prod

ENV RAILS_ENV=production \
    PORT=8080 \
    AWS_LWA_READINESS_CHECK_PATH=/up

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 \
    /lambda-adapter /opt/extensions/lambda-adapter
COPY --chown=rails:rails bin/docker-entrypoint bin/docker-entrypoint

EXPOSE 8080
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
