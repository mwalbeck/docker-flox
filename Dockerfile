FROM golang:1.16.5-buster@sha256:9d8f70f7f67e461ae75c148ee66394f4242f4b359c27222c31aeea1851c39d8f as supercronic

# renovate: datasource=github-tags depName=aptible/supercronic versioning=semver
ENV SUPERCRONIC_VERSION v0.1.12

RUN set -ex; \
    git clone --branch $SUPERCRONIC_VERSION https://github.com/aptible/supercronic; \
    cd supercronic; \
    go mod vendor; \
    go install;

FROM mwalbeck/composer:1.10.22-php7.4@sha256:8667387724540cbab92bed03f6a0aee88dbb26f021c945b00745ef255649d2eb AS composer

ENV FLOX_VERSION master

RUN set -ex; \
    \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /tmp/flox; \
    cd /tmp/flox/backend; \
    composer --no-cache install;

FROM php:7.4.20-fpm-buster@sha256:0107641c80442fb1c8fc6752772ceff685fb213951a27b6e8249d9d25896a4e6

COPY --from=composer /tmp/flox /usr/share/flox
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

VOLUME [ "/var/www/flox" ]
WORKDIR /var/www/flox

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
