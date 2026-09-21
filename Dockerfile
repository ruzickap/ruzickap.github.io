FROM ruby:4-slim@sha256:815184398ba6e53baf80faf8b9338789b6c66823e2324fa9cf73cd0332195cd1 AS build

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

FROM nginxinc/nginx-unprivileged:1.31.6-alpine-slim@sha256:2186f829d5390dc6217900279bcfbc0836a947f331980fd40d5be7d3aff5515a

# renovate: datasource=docker depName=nginxinc/nginx-unprivileged versioning=docker
LABEL org.opencontainers.image.base.name="nginxinc/nginx-unprivileged:1.31.6-alpine-slim@sha256:2186f829d5390dc6217900279bcfbc0836a947f331980fd40d5be7d3aff5515a"

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
