FROM debian:10.6-slim@sha256:bb5473161a03d24b397c46778e58f845e29f1ce42a2953666ef8289f00afda42 AS prep
ENV FLOX_VERSION master
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    ; \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /flox;

FROM composer:1.10.17@sha256:8d37a3118fc4dc5408f014faab1c3d6f9fbed7322f2cf887443f1bff7e722f5d AS composer
COPY --from=prep /flox /flox
RUN set -ex; \
    \
    cd /flox/backend; \
    composer install;

FROM php:7.4.12-fpm-buster@sha256:ed5f18ce68f67f7fdff07a75a61c68c90a7c93c1568021b003dd41059358ad5e
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
