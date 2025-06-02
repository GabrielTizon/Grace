#!/bin/bash
timeout 30s bash -c "until pg_isready -h db -U user; do echo 'Waiting for database...'; sleep 2; done"
if [ $? -ne 0 ]; then
    echo "Database connection failed"
    exit 1
fi

echo "PHP-FPM listen directive:"
grep 'listen' /usr/local/etc/php-fpm.conf
exec php-fpm --fpm-config /usr/local/etc/php-fpm.conf