FROM debian:10.7-slim@sha256:a4ad900bf58bf5973e034b4df1b99150a42f2a7cbfa424241839d5b44bc4dc58 AS prep
ENV FLOX_VERSION master
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    ; \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /flox;

FROM composer:1.10.19@sha256:be23de856144db43720e77d4ad86e601c334372f49e3b76d26efb9a7d5edf076 AS composer
COPY --from=prep /flox /flox
RUN set -ex; \
    \
    cd /flox/backend; \
    composer install;

FROM php:7.4.13-fpm-buster@sha256:6619b207fdcf869046efd9eca99681d224ee664572039c30a977e5383028cb62
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
