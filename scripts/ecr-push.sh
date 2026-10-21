#!/bin/bash
# ============================================
# FreshBox SpA - Build y Push imagenes a ECR
# Evaluación Parcial 2 - Arquitectura Cloud ARY1102
# ============================================
# Ejecutar desde la raíz del proyecto
# Construye las imágenes y las sube a los repositorios de FreshBox

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Account ID: $ACCOUNT_ID ==="
echo "=== Region: $REGION ==="

# Login en ECR
echo "=== Autenticando en ECR ==="
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Crear repositorios ECR (si no existen)
echo "=== Creando repositorios ECR ==="
REPOS=("freshbox-frontend" "freshbox-get-products" "freshbox-create-product" "freshbox-update-product" "freshbox-delete-product")

for REPO in "${REPOS[@]}"; do
    aws ecr create-repository --repository-name $REPO --region $REGION 2>/dev/null || echo "Repo $REPO ya existe"
done

# Build imagenes (ARM64 para nodos Graviton)
echo "=== Construyendo imagenes Docker (ARM64) ==="
docker build --platform linux/arm64 -t freshbox-frontend ./microservicioEKSFrontend
docker build --platform linux/arm64 -t freshbox-get-products ./microserviciosEKSBackend/get-products
docker build --platform linux/arm64 -t freshbox-create-product ./microserviciosEKSBackend/create-product
docker build --platform linux/arm64 -t freshbox-update-product ./microserviciosEKSBackend/update-product
docker build --platform linux/arm64 -t freshbox-delete-product ./microserviciosEKSBackend/delete-product

# Tag imagenes
echo "=== Etiquetando imagenes ==="
docker tag freshbox-frontend $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-frontend:latest
docker tag freshbox-get-products $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-get-products:latest
docker tag freshbox-create-product $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-create-product:latest
docker tag freshbox-update-product $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-update-product:latest
docker tag freshbox-delete-product $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-delete-product:latest

# Push imagenes a ECR
echo "=== Subiendo imagenes a ECR ==="
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-frontend:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-get-products:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-create-product:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-update-product:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/freshbox-delete-product:latest

echo "=== Push completado ==="
echo "=== Imágenes alojadas en ECR listas para ser consumidas por EKS ==="