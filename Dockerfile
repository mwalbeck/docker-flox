FROM mwalbeck/supercronic:0.2.26@sha256:0dbfab92ad908fcab1beab66ef470277715f0fca436dced38be3df8ee3ce3c13 as supercronic

FROM mwalbeck/composer:1.10.26-php7.4@sha256:92d996f49f4c61c18baa6c7566d1b89a46d1f69f5922481c36e77664c0c05af3 AS composer

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
