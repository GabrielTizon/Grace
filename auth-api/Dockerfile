FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    libpq-dev \
    git \
    libzip-dev \
    postgresql-client \
    && docker-php-ext-install pdo pdo_pgsql zip \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /app

COPY composer.json .
RUN composer install --prefer-dist --no-interaction --optimize-autoloader --verbose || { echo "Composer install failed"; exit 1; }

COPY src/ .
RUN chown -R www-data:www-data /app

COPY php-fpm.conf /usr/local/etc/php-fpm.conf

COPY entrypoint.sh /entrypoint.sh


RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh


RUN chmod +x /entrypoint.sh

EXPOSE 9001

ENTRYPOINT ["/entrypoint.sh"]