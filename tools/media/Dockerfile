FROM node:24.19.0-bookworm-slim@sha256:a9f5f7c91a432850b2a8a7797adf5eadb6c733ceed61167806cee7ea7fbc29df

# Debian drops superseded versions from the archive, so a pinned package breaks
# the build the next time the base image moves.
# hadolint ignore=DL3008
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      awscli \
      ca-certificates \
      ffmpeg \
      file \
      git \
      jq \
      libimage-exiftool-perl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY eslint.config.js ./
COPY check-metadata.sh ./
COPY src/ ./src/
COPY test/ ./test/

RUN chmod 0555 check-metadata.sh

ENV MEDIA_METADATA_CHECK=/app/check-metadata.sh \
    NODE_ENV=production

ENTRYPOINT ["node", "/app/src/cli.js"]
CMD ["check"]
