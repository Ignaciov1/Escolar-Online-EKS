#!/bin/bash
set -e

echo "=== Iniciando Despliegue Automatizado de EscolarOnline ==="

# --- 0. Variables ---
REGION="us-east-1"
CLUSTER_NAME="escolaronline-cluster"
ACCOUNT_ID="314870398011"
RDS_ENDPOINT="escolaronline-db.cb1ojeyuxu78.us-east-1.rds.amazonaws.com"
REPO_DIR="/home/ubuntu/Escolar-Online-EKS"

# --- 1. Conexión y Base de Datos ---
echo "=== Fase 1: Conectando a EKS y configurando RDS ==="
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].CidrBlock" --output text)
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier escolaronline-db --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text)

# Se omite error si la regla ya existe
aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 3306 --cidr $VPC_CIDR 2>/dev/null || true

cd $REPO_DIR
mysql -h $RDS_ENDPOINT -u alumno -palumno123 < init.sql

# --- 2. Corrección de Puertos y Subida a ECR ---
echo "=== Fase 2: Limpiando puertos del frontend y subiendo imágenes a ECR ==="
# Quitar puertos estáticos para que el Ingress rutee correctamente de forma interna
sed -i "s/:3001//g" microservicioEKSFrontend/js/app.js
sed -i "s/:3002//g" microservicioEKSFrontend/js/app.js
sed -i "s/:3003//g" microservicioEKSFrontend/js/app.js
sed -i "s/:3004//g" microservicioEKSFrontend/js/app.js

chmod +x scripts/ecr-push.sh
./scripts/ecr-push.sh

# --- 3. Despliegue K8s ---
echo "=== Fase 3: Aplicando Manifiestos ==="
cd $REPO_DIR/k8s
sed -i "s/<ACCOUNT_ID>/$ACCOUNT_ID/g" *-deployment.yaml
sed -i "s/<RDS_ENDPOINT>/$RDS_ENDPOINT/g" configmap.yaml
sed -i "s/<RDS_ENDPOINT>/$RDS_ENDPOINT/g" secret.yaml

kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
kubectl apply -f get-products-deployment.yaml
kubectl apply -f get-products-service.yaml
kubectl apply -f create-product-deployment.yaml
kubectl apply -f create-product-service.yaml
kubectl apply -f update-product-deployment.yaml
kubectl apply -f update-product-service.yaml
kubectl apply -f delete-product-deployment.yaml
kubectl apply -f delete-product-service.yaml

# --- 4. ALB Controller e Ingress ---
echo "=== Fase 4: Configurando ALB Controller e Ingress ==="
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.5/cert-manager.yaml
sleep 30

curl -Lo v2_5_4_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_full.yaml
sed -i "s/your-cluster-name/$CLUSTER_NAME/g" v2_5_4_full.yaml
sed -i "s/--cluster-name=$CLUSTER_NAME/--cluster-name=$CLUSTER_NAME\n        - --aws-region=$REGION\n        - --aws-vpc-id=$VPC_ID/g" v2_5_4_full.yaml
kubectl apply -f v2_5_4_full.yaml

# Parche IMDSv2 para nodos EC2 en AWS Academy
NODES=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
for NODE in $NODES; do
  aws ec2 modify-instance-metadata-options --instance-id $NODE --http-put-response-hop-limit 2
done

kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
sleep 15

# Creación del Ingress Avanzado
cat << 'EOF' > ingress-advanced.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: escolaronline-ingress
  namespace: escolaronline
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/conditions.get-products: >
      [{"field":"http-request-method", "httpRequestMethodConfig":{"values":["GET", "OPTIONS"]}}]
    alb.ingress.kubernetes.io/conditions.create-product: >
      [{"field":"http-request-method", "httpRequestMethodConfig":{"values":["POST"]}}]
    alb.ingress.kubernetes.io/conditions.update-product: >
      [{"field":"http-request-method", "httpRequestMethodConfig":{"values":["PUT"]}}]
    alb.ingress.kubernetes.io/conditions.delete-product: >
      [{"field":"http-request-method", "httpRequestMethodConfig":{"values":["DELETE"]}}]
spec:
  rules:
  - http:
      paths:
      - path: /api/products
        pathType: Prefix
        backend:
          service:
            name: get-products
            port:
              number: 3001
      - path: /api/products
        pathType: Prefix
        backend:
          service:
            name: create-product
            port:
              number: 3002
      - path: /api/products
        pathType: Prefix
        backend:
          service:
            name: update-product
            port:
              number: 3003
      - path: /api/products
        pathType: Prefix
        backend:
          service:
            name: delete-product
            port:
              number: 3004
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
EOF

kubectl apply -f ingress-advanced.yaml

# --- 5. HPA ---
echo "=== Fase 5: Configurando Autoescalado (HPA) ==="
kubectl apply -f hpa-get-products.yaml
kubectl apply -f hpa-create-product.yaml
kubectl apply -f hpa-update-product.yaml
kubectl apply -f hpa-delete-product.yaml

echo "=== Despliegue Finalizado ==="
echo "Espera un par de minutos y revisa tu DNS público ejecutando: kubectl get ingress -n escolaronline"