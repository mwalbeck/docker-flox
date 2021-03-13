FROM golang:1.16.2-buster@sha256:b14b26e3cfd8bcfd33eb5f5a6049cf131f6a9ae2723eed0721a0496f8579d7ef as supercronic

# renovate: datasource=github-tags depName=aptible/supercronic versioning=semver
ENV SUPERCRONIC_VERSION v0.1.12

RUN set -ex; \
    git clone --branch $SUPERCRONIC_VERSION https://github.com/aptible/supercronic; \
    cd supercronic; \
    go mod vendor; \
    go install;

FROM debian:10.8-slim@sha256:8bf6c883f182cfed6375bd21dbf3686d4276a2f4c11edc28f53bd3f6be657c94 AS prep

ENV FLOX_VERSION master

RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    ; \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /flox;

FROM composer:1.10.19@sha256:594befc8126f09039ad17fcbbd2e4e353b1156aba20556a6c474a8ed07ed7a5a AS composer

COPY --from=prep /flox /flox

RUN set -ex; \
    \
    cd /flox/backend; \
    composer install;

FROM php:7.4.16-fpm-buster@sha256:74d0c581b97d7d882fdf18ea13a3ddd328408fc76e38b8a93d27dcdd0bf91ad1

COPY --from=composer /flox /usr/share/flox
COPY --from=supercronic /go/bin/supercronic /usr/local/bin/supercronic

RUN set -ex; \
    \
    groupadd --system foo; \
    useradd --no-log-init --system --gid foo --create-home foo; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        supervisor \
        gosu \
        sqlite3 \
        rsync \
        libpq5 \
        libpq-dev \
    ; \
    chmod +x /usr/local/bin/supercronic; \
    echo '* * * * * php /var/www/flox/backend/artisan schedule:run >> /dev/null 2>&1' > /crontab; \
    \
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    \
    mkdir -p \
        /var/log/supervisord \
        /var/run/supervisord \
        /var/www/flox \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        pdo_mysql \
        pdo_pgsql \
        opcache \
    ; \
    apt-get purge -y --autoremove libpq-dev; \
    rm -rf /var/lib/apt/lists/*;

COPY entrypoint.sh /entrypoint.sh
COPY supervisord.conf /supervisord.conf

WORKDIR /var/www/flox

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
