FROM debian:10.5-slim@sha256:8d81110c3f93a777e3f4053a6b18b70e4a1003655b8c2664bdf18b19043f99d9 AS prep
ENV FLOX_VERSION master
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    ; \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /flox;

FROM composer:1.10.13@sha256:5821c81e84f77906e6ae8c9a2d016d4d635669ca595b12e949fcea518d6ed415 AS composer
COPY --from=prep /flox /flox
RUN set -ex; \
    \
    cd /flox/backend; \
    composer install;

FROM php:7.4.11-fpm-buster@sha256:e3fa9c1a071a64163b2baed1e394e32b23a5d420f11e31a18a2affc1c1cb07aa
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
