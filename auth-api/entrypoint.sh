#!/bin/bash

# Wait for DB
timeout 30s bash -c "until pg_isready -h db -U user; do echo 'Waiting for database...'; sleep 2; done"
if [ $? -ne 0 ]; then
    echo "Database connection failed"
    exit 1
fi

# Start PHP-FPM only
exec php-fpm
