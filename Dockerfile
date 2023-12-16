FROM mwalbeck/supercronic:0.2.29@sha256:cc5f7078ec5204acec8de98a6c7df32e191b3c6e077af11972da7f11f19d8071 as supercronic

FROM mwalbeck/composer:1.10.27-php7.4@sha256:59af589cdb4980afa77364ff9c448ff0e02d6ee2b119009cd8396d6bf45a12d3 AS composer

ENV FLOX_VERSION master

RUN set -ex; \
    \
    git clone --branch $FLOX_VERSION https://github.com/devfake/flox.git /tmp/flox; \
    cd /tmp/flox/backend; \
    composer --no-cache install;

FROM php:7.4.33-fpm-bullseye@sha256:3ac7c8c74b2b047c7cb273469d74fc0d59b857aa44043e6ea6a0084372811d5b

COPY --from=composer /tmp/flox /usr/share/flox
COPY --from=supercronic /supercronic /usr/local/bin/supercronic

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
