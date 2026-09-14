FROM ruby:4-slim@sha256:58479f164d5947f852da27a4436c89bb986a811f959c40552bc7f6ccaabcc9c9 AS build

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update -qq && apt-get install -qqy --no-install-recommends build-essential git

# Set the current working directory in the container
WORKDIR /usr/src/app

# Copy over everything from our local directory to the container
COPY . .

# Install the required gems
RUN bundle install

ENV JEKYLL_ENV=production

# Generate our static site
RUN bundle exec jekyll build

################################################################################

FROM nginxinc/nginx-unprivileged:1.31.5-alpine-slim@sha256:736aa11ab9f9c320825722e411661c64559881e15e77f37137eef168ebe9515c

# renovate: datasource=docker depName=nginxinc/nginx-unprivileged versioning=docker
LABEL org.opencontainers.image.base.name="nginxinc/nginx-unprivileged:1.31.5-alpine-slim@sha256:736aa11ab9f9c320825722e411661c64559881e15e77f37137eef168ebe9515c"

COPY --from=build /usr/src/app/_site /usr/share/nginx/html/

RUN printf '%s\n' > /etc/nginx/conf.d/health.conf \
    'server {' \
    '    listen 8081;' \
    '    location / {' \
    '        access_log off;' \
    '        add_header Content-Type text/plain;' \
    '        return 200 "healthy\n";' \
    '    }' \
    '}'

USER 101

# Healthcheck to make sure container is ready
HEALTHCHECK --interval=5m --timeout=3s CMD ["curl", "--fail", "http://localhost:8081"]
