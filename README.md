# docker-flox

[![Build Status](https://build.walbeck.it/api/badges/mwalbeck/docker-flox/status.svg?ref=refs/heads/master)](https://build.walbeck.it/mwalbeck/docker-flox)
![Docker Pulls](https://img.shields.io/docker/pulls/mwalbeck/flox)

This is a docker image for [flox](https://github.com/devfake/flox) built from the current master branch. You can find the image on [Docker Hub](https://hub.docker.com/r/mwalbeck/flox) and the source code can be found [here](https://git.walbeck.it/mwalbeck/docker-flox) with a mirror on [github](https://github/mwalbeck/docker-flox).

## Usage

This is a php-fpm based image, which means you need another container to act as the webserver. For this I would recommend nginx and you can find an example nginx config below.

The container can be configured with environment variables and you can see the list of options below. You can also specify an arbitrary UID and GID for the container to run as with the default being 1000 for both.

The container support using Mariadb/MySQL or PostreSQL as the database instead of sqlite, and is the reason why the image is currently being built from master instead of the latest release.

OBS: The very first time you start the container `FLOX_DB_INIT` should be set to true. Afterwards it should be set to false and the container should be restarted. `FLOX_DB_INIT` should only be set when you want to initialise a new database. If you don't set it to false after the first run then the container will failed to start.

## Config options

| Variable name             | Default value                                  | Description                                                                                                                      |
| ------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| UID                       | 1000                                           | The user id the container should run as.                                                                                         |
| GID                       | 1000                                           | The group id the container should run as.                                                                                        |
| FLOX_DB_INIT              | false                                          | If the database should be initialised when the container is started. Should only be true the first time you start the container. |
| FLOX_DB_CONNECTION        | sqlite                                         | Which database type to use. Can be either `sqlite`, `mysql` or `pgsql`                                                           |
| FLOX_DB_NAME              | /var/www/flox/backend/database/database.sqlite | The name of the database or when using sqlite the filepath of the database file.                                                 |
| FLOX_DB_USER              | -                                              | The database user. Only applicable when using either `mysql` or `pgsql`                                                          |
| FLOX_DB_PASS              | -                                              | The database users password. Only applicable when using either `mysql` or `pgsql`                                                |
| FLOX_DB_HOST              | localhost                                      | IP address or hostname for the database. Only applicable when using either `mysql` or `pgsql`                                    |
| FLOX_DB_PORT              | 3306                                           | The port the database is listening on. Only applicable when using either `mysql` or `pgsql`                                      |
| FLOX_ADMIN_USER           | admin                                          | Username of the admin account                                                                                                    |
| FLOX_ADMIN_PASS           | admin                                          | Password of the admin account                                                                                                    |
| FLOX_APP_URL              | http://localhost                               | The root URL for flox                                                                                                            |
| FLOX_APP_ENV              | local                                          | The application environment. Can either be `local` or `production`                                                               |
| FLOX_APP_DEBUG            | false                                          | Debug mode. Can either be `true` or `false`                                                                                      |
| FLOX_TIMEZONE             | UTC                                            | Your timezone. Look [here](https://www.php.net/manual/en/timezones.php) for timezone names                                       |
| FLOX_DAILY_REMINDER_TIME  | 10:00                                          | When to receive a daily reminder via email about tv episodes and movies coming out today.                                        |
| FLOX_WEEKLY_REMINDER_TIME | 20:00                                          | When to receive a weekly reminder via email about tv episodes and movies that has come out during the last 7 days.               |
| FLOX_TRANSLATION          | -                                              | Which language flox should use.                                                                                                  |
| FLOX_DATE_FORMAT_PATTERN  | d.m.y                                          |                                                                                                                                  |
| FLOX_REDIS_HOST           | localhost                                      | IP address or hostname of your redis instance.                                                                                   |
| FLOX_REDIS_PASSWORD       | null                                           | Password for your redis instance, if applicable.                                                                                 |
| FLOX_REDIS_PORT           | 6379                                           | The port used by your redis instance.                                                                                            |
| FLOX_MAIL_DRIVER          | smtp                                           | Which mail driver to use. Checkout the Laravel documentation for more options                                                    |
| FLOX_MAIL_HOST            | -                                              | IP address or hostname for your SMTP server                                                                                      |
| FLOX_MAIL_PORT            | 587                                            | Port to use for sending mail.                                                                                                    |
| FLOX_MAIL_USERNAME        | -                                              | SMTP username                                                                                                                    |
| FLOX_MAIL_PASSWORD        | -                                              | SMTP password                                                                                                                    |
| FLOX_MAIL_ENCRYPTION      | tls                                            | Mail transport encryption                                                                                                        |
| TMDB_API_KEY              | -                                              | An API key for TMDB. Look [here](https://www.themoviedb.org/faq/api) for more info                                               |

## Example docker-compose

```
version: '2'

volumes:
  flox:

networks:
  frontend:

services:
  flox:
    image: mwalbeck/getgrav:latest
    restart: on-failure:5
    networks:
      - frontend
    volumes:
      - flox:/var/www/flox
    environment:
      FLOX_ADMIN_USER: "something"
      FLOX_ADMIN_PASS: "something"
      FLOX_APP_URL: "something"
      TMDB_API_KEY: "something"
      FLOX_DB_INIT: true

  web:
    image: nginx:latest
    restart: on-failure:5
    networks:
      - frontend
    volumes:
      - flox:/var/www/flox:ro
      - /path/to/nginx:/etc/nginx:ro
    ports:
      - 80:80
      - 443:443
```

## Example nginx config

```
server {
    listen [::]:80;
    listen 80;
    server_name localhost;

    root /var/www/flox/public;

    index index.php;

    charset utf-8;

    location ~ /\. {
        access_log off;
        log_not_found off;
        deny all;
    }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location = /index.php {
        fastcgi_pass flox:9000;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        try_files $fastcgi_script_name =404;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    location ~ \.php$ { return 403; }
}
```
