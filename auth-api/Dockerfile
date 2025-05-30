FROM php:8.2-apache

# Instala dependências
RUN docker-php-ext-install pdo pdo_pgsql

# Instala Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Instala dependências do projeto
COPY . /var/www/html
WORKDIR /var/www/html
RUN composer install

# Habilita rewrite para Slim
RUN a2enmod rewrite
COPY ./apache-config.conf /etc/apache2/sites-available/000-default.conf

EXPOSE 80
