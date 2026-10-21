FROM composer:2 AS composer

FROM php:8.2.34-apache-bookworm@sha256:b7a1e3d89a445c94f47d5292f7a5268fa4fc848ff378c780b91aca013491dd87

# shortcut: 8.2.35 image manifests are not published yet; use the official patched source until they are available.
ENV PHP_VERSION=8.2.35 \
    PHP_URL=https://www.php.net/distributions/php-8.2.35.tar.xz \
    PHP_ASC_URL=https://www.php.net/distributions/php-8.2.35.tar.xz.asc \
    PHP_SHA256=5737b98601fe5ab1b8c5db0c82ed3158acb9283ed3081ffe2faffb9ac81455e6

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS apache2-dev libargon2-dev libcurl4-openssl-dev \
        libonig-dev libreadline-dev libsodium-dev libsqlite3-dev \
        libssl-dev libxml2-dev zlib1g-dev libmagickwand-dev libpq-dev \
        gettext-base openssl unzip; \
    configureOptions="$(php-config --configure-options)"; \
    case "$configureOptions" in *--with-apxs2*) ;; *) exit 1 ;; esac; \
    curl --fail --show-error --location --retry 3 "$PHP_URL" -o /usr/src/php.tar.xz; \
    echo "$PHP_SHA256  /usr/src/php.tar.xz" | sha256sum --check --strict; \
    docker-php-source delete; \
    docker-php-source extract; \
    export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
    cd /usr/src/php; \
    eval "set -- $configureOptions"; \
    ./configure "$@"; \
    make -j2; \
    make install; \
    cp php.ini-production "$PHP_INI_DIR/php.ini"; \
    cd /; \
    docker-php-source delete; \
    docker-php-ext-install -j2 bcmath ftp pdo_mysql pdo_pgsql; \
    pecl install imagick-3.8.1; \
    pecl install redis-6.3.0; \
    docker-php-ext-enable imagick redis; \
    docker-php-source delete; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark gettext-base openssl unzip > /dev/null; \
    { find /usr/local -type f \( -executable -o -name '*.so' \) -exec ldd '{}' ';'; \
      ldd /usr/lib/apache2/modules/libphp.so; } \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) next; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | awk 'sub(":$", "", $1) { print $1 }' \
        | sort -u \
        | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/* /tmp/pear; \
    ! ldd /usr/lib/apache2/modules/libphp.so | grep 'not found'; \
    php -r 'if (PHP_VERSION_ID < 80235 || PHP_VERSION_ID >= 80300) { throw new RuntimeException("Patched PHP 8.2 required"); } foreach (["bcmath", "ftp", "imagick", "pdo_mysql", "pdo_pgsql", "redis"] as $ext) { if (!extension_loaded($ext)) { throw new RuntimeException("Missing extension: ".$ext); } }'

COPY --from=composer /usr/bin/composer /usr/local/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/lsky-composer \
    WEB_PORT=8089 \
    HTTPS_PORT=8088

WORKDIR /var/www/lsky
COPY composer.json composer.lock ./
RUN composer --no-interaction --no-plugins --no-scripts check-platform-reqs --lock --no-dev \
    && composer --no-interaction --no-plugins --no-scripts install --no-dev --prefer-dist --no-progress --no-autoloader

COPY . .
RUN set -eux; \
    composer --no-interaction --no-plugins --no-scripts dump-autoload --no-dev --optimize; \
    composer --no-interaction --no-plugins --no-scripts check-platform-reqs --no-dev; \
    composer clear-cache; \
    mkdir -p storage/app/uploads storage/app/public storage/logs \
        storage/framework/cache/data storage/framework/sessions \
        storage/framework/views bootstrap/cache /var/www/data; \
    ln -s ../storage/app/uploads public/i; \
    chown www-data:www-data /var/www/data; \
    a2enmod rewrite ssl; \
    a2dissite 000-default; \
    printf 'ServerName localhost\nServerTokens Prod\nServerSignature Off\n' > /etc/apache2/conf-available/lsky.conf; \
    a2enconf lsky

COPY docker/php.ini /usr/local/etc/php/conf.d/lsky.ini
COPY docker/apache-site.conf.template docker/ports.conf.template /etc/apache2/templates/
COPY docker/entrypoint.sh /usr/local/bin/lsky-entrypoint
RUN chmod 755 /usr/local/bin/lsky-entrypoint

WORKDIR /var/www/html
VOLUME /var/www/html
EXPOSE 8089 8088
ENTRYPOINT ["lsky-entrypoint"]
CMD ["apache2-foreground"]
