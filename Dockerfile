# --- Build Stage ---
FROM composer:latest as build
ENV APP_ENV=prod
WORKDIR /app/
COPY composer.json composer.lock /app/
RUN composer install --no-scripts --no-autoloader \
    && composer dump-autoload --optimize

# --- Runtime Stage ---
FROM php:8.3-apache

# PHP config for Cloud Run
RUN docker-php-ext-install -j "$(nproc)" opcache \
 && echo "memory_limit = -1\nmax_execution_time = 0\nupload_max_filesize = 1M\npost_max_size = 1M\nopcache.enable=On\nopcache.validate_timestamps=Off\nopcache.memory_consumption=32" > "$PHP_INI_DIR/conf.d/cloud-run.ini"

WORKDIR /var/www

# Apache config
COPY docker/vhost.conf /etc/apache2/sites-available/000-default.conf

# Copy project
COPY --from=build /app/vendor /var/www/vendor
COPY . /var/www/

# Permissions
RUN chown -R www-data:www-data /var/www/

# Replace hardcoded port with Cloud Run port
RUN sed -i 's/80/${PORT}/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

# Enable URL rewriting
RUN a2enmod rewrite

# Use production php.ini
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

USER www-data
ENV APP_ENV=prod

# Symfony prep (optional, adjust for your project)
RUN php bin/console cache:clear --no-warmup \
 && php bin/console cache:warmup \
 && php bin/console importmap:install \
 && php bin/console assets:install \
 && php bin/console asset-map:compile

CMD ["apache2-foreground"]
