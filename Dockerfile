FROM ruby:4-slim@sha256:5c9fd5574701c4af0ec5b8a5c4b32d7801c6b98175234fdac4f9e14094c5cf5b AS build

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

FROM nginxinc/nginx-unprivileged:1.31.6-alpine-slim@sha256:dcc9bf9c084901dddbbce305130a7295c5637b6a8fce3e29cf678d86336982e4

# renovate: datasource=docker depName=nginxinc/nginx-unprivileged versioning=docker
LABEL org.opencontainers.image.base.name="nginxinc/nginx-unprivileged:1.31.6-alpine-slim@sha256:dcc9bf9c084901dddbbce305130a7295c5637b6a8fce3e29cf678d86336982e4"

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
