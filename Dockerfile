FROM debian:10.4-slim@sha256:7c459309b9a5ec1683ef3b137f39ce5888f5ad0384e488ad73c94e0243bc77d4 AS prep
ENV FLOX_VERSION master
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    ; \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /flox;

FROM composer:1.10.9@sha256:f68aacb3bf0d8d10a6efb5769873fc006d121f64756c9d7b054af634fd934e41 AS composer
COPY --from=prep /flox /flox
RUN set -ex; \
    \
    cd /flox/backend; \
    composer install;

FROM php:7.3.20-fpm-buster@sha256:80c7f7607d6117cb9625ca5aeea3ec21f5e576a922b2696c24a1835a44ef4643
COPY --from=composer /flox /usr/share/flox
RUN set -ex; \
    \
    groupadd --system foo; \
    useradd --no-log-init --system --gid foo --create-home foo; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        supervisor \
        busybox-static \
        gosu \
        sqlite3 \
        rsync \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    \
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    \
    mkdir -p \
        /var/log/supervisord \
        /var/run/supervisord \
        /var/spool/cron/crontabs \
        /var/www/flox \
    ; \
    echo '* * * * * php /var/www/flox/backend/artisan schedule:run >> /dev/null 2>&1' > /var/spool/cron/crontabs/foo;

RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libpq-dev \
    ; \
    \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        pdo_mysql \
        pdo_pgsql \
        opcache \
    ; \
    \
    # reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*;

COPY entrypoint.sh /entrypoint.sh
COPY cron.sh /cron.sh
COPY supervisord.conf /supervisord.conf

WORKDIR /var/www/flox

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
