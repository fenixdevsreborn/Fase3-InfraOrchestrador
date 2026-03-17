#!/usr/bin/env bash
# /opt/fcg-fenix/usersapi/deploy.sh
# Uso: ./deploy.sh [IMAGE_TAG]
# Sem argumento: pull da tag atual em .env e sobe.
# Com argumento: atualiza .env com a nova tag, pull e sobe (deploy ou rollback).

set -e
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR"

if [ -n "$1" ]; then
  TAG="$1"
  if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
    sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$TAG/" .env
  else
    echo "IMAGE_TAG=$TAG" >> .env
  fi
  echo "Using image tag: $TAG"
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REGISTRY=$(grep '^ECR_REGISTRY=' .env | cut -d= -f2-)
REGISTRY_HOST="${ECR_REGISTRY%/*}"
aws ecr get-login-password --region "$AWS_REGION" | sudo docker login --username AWS --password-stdin "$REGISTRY_HOST"

sudo docker compose pull
sudo docker compose up -d

echo "Deploy finished. Current tag: $(grep '^IMAGE_TAG=' .env 2>/dev/null | cut -d= -f2-)"
