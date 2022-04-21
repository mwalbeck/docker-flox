FROM golang:1.18.1-bullseye@sha256:dee664002d1d39e222c7f2c4ba8652c02f1d2dc82e9be7235417f0d53581703d as supercronic

# renovate: datasource=github-tags depName=aptible/supercronic versioning=semver
ENV SUPERCRONIC_VERSION v0.1.12

RUN set -ex; \
    git clone --branch $SUPERCRONIC_VERSION https://github.com/aptible/supercronic; \
    cd supercronic; \
    go mod vendor; \
    go install;

FROM mwalbeck/composer:1.10.26-php7.4@sha256:db6e8411384ee73c2a40d1e74d9d7a53a4102c7a7dd86b8b78c5550ada2c726b AS composer

ENV FLOX_VERSION master

RUN set -ex; \
    \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /tmp/flox; \
    cd /tmp/flox/backend; \
    composer --no-cache install;

FROM php:7.4.29-fpm-bullseye@sha256:49ecd2a36ec4c3e70b0aafb59916bd8090061268410d2ede66b5cf595d0aaf11

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
    { \
        echo "upload_max_filesize=128M"; \
        echo "post_max_size=128M"; \
    } > /usr/local/etc/php/conf.d/flox.ini; \
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
