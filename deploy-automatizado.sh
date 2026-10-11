#!/bin/bash
set -e

# --- Colores y Formato ---
C_BLUE='\e[1;34m'
C_GREEN='\e[1;32m'
C_YELLOW='\e[1;33m'
C_CYAN='\e[1;36m'
C_RESET='\e[0m'

echo -e "${C_BLUE}=================================================================${C_RESET}"
echo -e "${C_CYAN}🚀 INICIANDO DESPLIEGUE AUTOMATIZADO DE ESCOLARONLINE - EKS 🚀${C_RESET}"
echo -e "${C_BLUE}=================================================================${C_RESET}\n"

# --- 0. Instalación de Dependencias ---
echo -e "${C_YELLOW}[Paso 0] Verificando e instalando dependencias...${C_RESET}"
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y docker.io git unzip curl mysql-client jq > /dev/null 2>&1

sudo systemctl enable --now docker > /dev/null 2>&1
sudo usermod -aG docker ubuntu

if ! command -v aws &> /dev/null; then
    echo -e "   ${C_CYAN}-> Instalando AWS CLI v2...${C_RESET}"
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install > /dev/null
    rm -rf awscliv2.zip aws/
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "   ${C_CYAN}-> Instalando kubectl...${C_RESET}"
    curl -s -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.0/2024-01-04/bin/linux/arm64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
fi
echo -e "${C_GREEN}✔ Dependencias instaladas y configuradas.${C_RESET}\n"

# --- Variables Dinámicas ---
REGION="us-east-1"
CLUSTER_NAME="escolaronline-cluster"
ACCOUNT_ID="314870398011"
REPO_DIR="/home/ubuntu/Escolar-Online-EKS"

# --- 1. Conexión y Base de Datos ---
echo -e "${C_YELLOW}[Paso 1] Conectando a EKS y configurando base de datos RDS...${C_RESET}"
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME > /dev/null 2>&1

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].CidrBlock" --output text)
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier escolaronline-db --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text)
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier escolaronline-db --query "DBInstances[0].Endpoint.Address" --output text)

echo -e "   ${C_CYAN}-> DNS Dinámico de RDS: ${C_RESET}$RDS_ENDPOINT"
aws ec2 authorize-security-group-ingress --group-id $RDS_SG --protocol tcp --port 3306 --cidr $VPC_CIDR 2>/dev/null || true

cd $REPO_DIR
mysql -h $RDS_ENDPOINT -u alumno -palumno123 < init.sql 2>/dev/null || true
echo -e "${C_GREEN}✔ Base de datos poblada exitosamente.${C_RESET}\n"

# --- 2. Preparación y ECR ---
echo -e "${C_YELLOW}[Paso 2] Configurando frontend y subiendo imágenes a ECR...${C_RESET}"
sed -i "s/:3001//g" microservicioEKSFrontend/js/app.js
sed -i "s/:3002//g" microservicioEKSFrontend/js/app.js
sed -i "s/:3003//g" microservicioEKSFrontend/js/app.js
sed -i "s/:3004//g" microservicioEKSFrontend/js/app.js

chmod +x scripts/ecr-push.sh
aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com > /dev/null 2>&1
sudo ./scripts/ecr-push.sh > /dev/null 2>&1 || true
echo -e "${C_GREEN}✔ Imágenes compiladas y alojadas en ECR.${C_RESET}\n"

# --- 3. Despliegue de Kubernetes ---
echo -e "${C_YELLOW}[Paso 3] Desplegando manifiestos de Kubernetes...${C_RESET}"
cd $REPO_DIR/k8s
sed -i "s/<ACCOUNT_ID>/$ACCOUNT_ID/g" *-deployment.yaml
sed -i "s/<RDS_ENDPOINT>/$RDS_ENDPOINT/g" configmap.yaml
sed -i "s/<RDS_ENDPOINT>/$RDS_ENDPOINT/g" secret.yaml

kubectl apply -f namespace.yaml > /dev/null
kubectl apply -f configmap.yaml > /dev/null
kubectl apply -f secret.yaml > /dev/null
kubectl apply -f frontend-deployment.yaml > /dev/null
kubectl apply -f frontend-service.yaml > /dev/null
kubectl apply -f get-products-deployment.yaml > /dev/null
kubectl apply -f get-products-service.yaml > /dev/null
kubectl apply -f create-product-deployment.yaml > /dev/null
kubectl apply -f create-product-service.yaml > /dev/null
kubectl apply -f update-product-deployment.yaml > /dev/null
kubectl apply -f update-product-service.yaml > /dev/null
kubectl apply -f delete-product-deployment.yaml > /dev/null
kubectl apply -f delete-product-service.yaml > /dev/null

kubectl rollout restart deployment get-products create-product update-product delete-product -n escolaronline > /dev/null || true

echo -e "${C_GREEN}✔ Microservicios desplegados en el clúster.${C_RESET}\n"

# --- 4. ALB Controller e Ingress ---
echo -e "${C_YELLOW}[Paso 4] Configurando Balanceador de Carga e Ingress...${C_RESET}"
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.5/cert-manager.yaml > /dev/null 2>&1 || true
sleep 30

curl -s -Lo v2_5_4_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_full.yaml
sed -i "s/your-cluster-name/$CLUSTER_NAME/g" v2_5_4_full.yaml
sed -i "s/--cluster-name=$CLUSTER_NAME/--cluster-name=$CLUSTER_NAME\n        - --aws-region=$REGION\n        - --aws-vpc-id=$VPC_ID/g" v2_5_4_full.yaml
kubectl apply -f v2_5_4_full.yaml > /dev/null 2>&1 || true

NODES=$(aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
for NODE in $NODES; do
  aws ec2 modify-instance-metadata-options --instance-id $NODE --http-put-response-hop-limit 2 > /dev/null 2>&1 || true
done

echo -e "   ${C_CYAN}-> Inyectando credenciales al ALB Controller...${C_RESET}"
export AWS_AK=$(awk -F'=' '/aws_access_key_id/ {print $2}' ~/.aws/credentials | tr -d ' ' | tr -d '\r')
export AWS_SK=$(awk -F'=' '/aws_secret_access_key/ {print $2}' ~/.aws/credentials | tr -d ' ' | tr -d '\r')
export AWS_ST=$(awk -F'=' '/aws_session_token/ {print $2}' ~/.aws/credentials | tr -d ' ' | tr -d '\r')

kubectl set env deployment aws-load-balancer-controller -n kube-system \
  AWS_ACCESS_KEY_ID=$AWS_AK \
  AWS_SECRET_ACCESS_KEY=$AWS_SK \
  AWS_SESSION_TOKEN=$AWS_ST || true

kubectl rollout restart deployment aws-load-balancer-controller -n kube-system > /dev/null 2>&1 || true

echo -e "   ${C_YELLOW}-> Esperando a que el ALB Controller esté 100% listo (esto evita el error del webhook)...${C_RESET}"
kubectl rollout status deployment aws-load-balancer-controller -n kube-system --timeout=180s || true
sleep 10

echo -e "   ${C_CYAN}-> Generando e importando certificado ACM para HTTPS...${C_RESET}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout alb_key.pem -out alb_cert.pem -subj "/CN=escolaronline-local.com/O=EscolarOnline" 2>/dev/null
CERT_ARN=$(aws acm import-certificate --certificate fileb://alb_cert.pem --private-key fileb://alb_key.pem --query "CertificateArn" --output text)

cat << INGRESS_EOF > ingress-advanced.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: escolaronline-ingress
  namespace: escolaronline
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: "$CERT_ARN"
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
INGRESS_EOF

kubectl apply -f ingress-advanced.yaml > /dev/null || true
echo -e "${C_GREEN}✔ Balanceador de Carga provisionado.${C_RESET}\n"

# --- 5. HPA ---
echo -e "${C_YELLOW}[Paso 5] Configurando Autoescalado (HPA)...${C_RESET}"
kubectl apply -f hpa-get-products.yaml > /dev/null || true
kubectl apply -f hpa-create-product.yaml > /dev/null || true
kubectl apply -f hpa-update-product.yaml > /dev/null || true
kubectl apply -f hpa-delete-product.yaml > /dev/null || true
echo -e "${C_GREEN}✔ Políticas de autoescalado activadas.${C_RESET}\n"

# --- 6. Habilitar Logs de EKS (Container Insights parcial) ---
echo -e "${C_YELLOW}[Paso 6] Habilitando Logs del Plano de Control en CloudWatch...${C_RESET}"
aws eks update-cluster-config \
  --name $CLUSTER_NAME \
  --region $REGION \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' > /dev/null 2>&1 || true
echo -e "${C_GREEN}✔ Logs del clúster configurados.${C_RESET}\n"

echo -e "${C_BLUE}=================================================================${C_RESET}"
echo -e "${C_CYAN}🎉 DESPLIEGUE FINALIZADO CON ÉXITO 🎉${C_RESET}"
echo -e "Espera un par de minutos y ejecuta ${C_YELLOW}kubectl get ingress -n escolaronline${C_RESET} para obtener tu URL pública."
echo -e "${C_BLUE}=================================================================${C_RESET}\n"