#!/bin/sh
set -eu

case "${1:-}" in
    apache2-foreground|apache2|apachectl)
        for port in "$WEB_PORT" "$HTTPS_PORT"; do
            case "$port" in ''|*[!0-9]*) echo 'Invalid Apache port' >&2; exit 1 ;; esac
            if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                echo 'Apache ports must be between 1 and 65535' >&2
                exit 1
            fi
        done
        if [ "$WEB_PORT" = "$HTTPS_PORT" ]; then
            echo 'WEB_PORT and HTTPS_PORT must differ' >&2
            exit 1
        fi
        envsubst '${WEB_PORT} ${HTTPS_PORT}' < /etc/apache2/templates/ports.conf.template > /etc/apache2/ports.conf
        envsubst '${WEB_PORT} ${HTTPS_PORT}' < /etc/apache2/templates/apache-site.conf.template > /etc/apache2/sites-enabled/lsky.conf

        cd /var/www/html
        if [ ! -f public/index.php ]; then
            if [ -n "$(find . -mindepth 1 -maxdepth 1 -print -quit)" ]; then
                echo 'Application volume is nonempty but public/index.php is missing; refusing to overwrite it.' >&2
                exit 1
            fi
            cp -a /var/www/lsky/. .
            chown -R www-data:www-data /var/www/html
        fi
        if [ ! -f vendor/autoload.php ] || [ ! -f vendor/composer/installed.json ]; then
            echo 'Application dependencies are missing; restore the complete application volume before starting.' >&2
            exit 1
        fi
        composer --no-interaction --no-plugins --no-scripts check-platform-reqs --no-dev

        if [ ! -s /etc/ssl/certs/ssl-cert-snakeoil.pem ] || [ ! -s /etc/ssl/private/ssl-cert-snakeoil.key ]; then
            openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj /CN=localhost \
                -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
                -out /etc/ssl/certs/ssl-cert-snakeoil.pem > /dev/null 2>&1
            chmod 600 /etc/ssl/private/ssl-cert-snakeoil.key
        fi
        apache2ctl -t
        ;;
esac

exec docker-php-entrypoint "$@"
