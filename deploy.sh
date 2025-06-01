#!/bin/bash

echo "Starting deployment..." | tee deploy.log

# Build images
echo "Building images..." | tee -a deploy.log
docker-compose build | tee -a deploy.log
if [ $? -ne 0 ]; then
    echo "Build failed. Check deploy.log." | tee -a deploy.log
    exit 1
fi

# Run containers
echo "Starting containers..." | tee -a deploy.log
docker-compose up -d | tee -a deploy.log
if [ $? -ne 0 ]; then
    echo "Deployment failed. Check deploy.log." | tee -a deploy.log
    exit 1
fi

# Health checks
echo "Running health checks..." | tee -a deploy.log
services=("auth-api" "record-api" "receive-send-api" "db" "redis")
for service in "${services[@]}"; do
    echo "Checking health of $service..." | tee -a deploy.log
    for i in {1..30}; do
        status=$(docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null)
        if [ "$status" = "healthy" ]; then
            echo "$service is healthy." | tee -a deploy.log
            break
        fi
        if [ $i -eq 30 ]; then
            echo "$service is not healthy. Check logs." | tee -a deploy.log
            exit 1
        fi
        sleep 2
    done
done

echo "Deployment successful!" | tee -a deploy.log