#!/bin/bash
# CloudMart Deployment Helper Script
# Run this after terraform apply to manage your application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get values from Terraform
get_terraform_output() {
    terraform output -raw $1 2>/dev/null || echo ""
}

EC2_IP=$(get_terraform_output ec2_public_ip)
KEY_FILE="cloudmart-key.pem"

if [ -z "$EC2_IP" ]; then
    echo -e "${RED}Error: Could not get EC2 IP. Run 'terraform apply' first${NC}"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}Error: Key file $KEY_FILE not found in current directory${NC}"
    exit 1
fi

# Main menu
show_menu() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     CloudMart Deployment Helper       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}EC2 IP:${NC} $EC2_IP"
    echo ""
    echo "1) Deploy JAR file"
    echo "2) SSH into server"
    echo "3) View application logs"
    echo "4) Restart application"
    echo "5) Check application status"
    echo "6) Test application health"
    echo "7) Show all Terraform outputs"
    echo "8) Generate application.yml"
    echo "9) Purge SQS queue"
    echo "0) Exit"
    echo ""
    read -p "Choose an option: " choice
}

# Deploy JAR
deploy_jar() {
    echo -e "${YELLOW}Building JAR...${NC}"
    mvn clean package -DskipTests

    echo -e "${YELLOW}Uploading JAR to EC2...${NC}"
    scp -i "$KEY_FILE" target/cloudmart-backend-0.0.1-SNAPSHOT.jar ec2-user@$EC2_IP:/home/ec2-user/app/app.jar

    echo -e "${YELLOW}Restarting application...${NC}"
    ssh -i "$KEY_FILE" ec2-user@$EC2_IP "sudo systemctl restart cloudmart"

    echo -e "${GREEN}✅ Deployment complete!${NC}"
    echo "View logs with option 3"
}

# SSH
ssh_connect() {
    echo -e "${YELLOW}Connecting to EC2...${NC}"
    ssh -i "$KEY_FILE" ec2-user@$EC2_IP
}

# View logs
view_logs() {
    echo -e "${YELLOW}Viewing logs (Ctrl+C to exit)...${NC}"
    ssh -i "$KEY_FILE" ec2-user@$EC2_IP "tail -f ~/app/log.txt"
}

# Restart app
restart_app() {
    echo -e "${YELLOW}Restarting application...${NC}"
    ssh -i "$KEY_FILE" ec2-user@$EC2_IP "sudo systemctl restart cloudmart"
    sleep 3
    ssh -i "$KEY_FILE" ec2-user@$EC2_IP "sudo systemctl status cloudmart"
    echo -e "${GREEN}✅ Restart complete${NC}"
}

# Check status
check_status() {
    echo -e "${YELLOW}Checking application status...${NC}"
    ssh -i "$KEY_FILE" ec2-user@$EC2_IP "sudo systemctl status cloudmart"
}

# Test health
test_health() {
    echo -e "${YELLOW}Testing application health...${NC}"
    response=$(curl -s -o /dev/null -w "%{http_code}" http://$EC2_IP:8080/actuator/health)

    if [ "$response" = "200" ]; then
        echo -e "${GREEN}✅ Application is healthy!${NC}"
        curl http://$EC2_IP:8080/actuator/health | jq .
    else
        echo -e "${RED}❌ Application is not responding (HTTP $response)${NC}"
    fi
}

# Show outputs
show_outputs() {
    echo -e "${YELLOW}Terraform Outputs:${NC}"
    terraform output
}

# Generate application.yml
generate_app_yml() {
    RDS_ENDPOINT=$(get_terraform_output rds_endpoint)
    S3_BUCKET=$(get_terraform_output s3_bucket_name)
    SQS_URL=$(get_terraform_output sqs_queue_url)
    SNS_ARN=$(get_terraform_output sns_topic_arn)

    echo -e "${YELLOW}Generating application.yml...${NC}"

    cat > application-generated.yml <<EOF
spring:
  application:
    name: cloudmart-backend

  profiles:
    active: prod

  datasource:
    url: jdbc:mysql://${RDS_ENDPOINT%:*}:3306/cloudmart?createDatabaseIfNotExist=true&useSSL=false&serverTimezone=UTC
    username: admin
    password: REPLACE_WITH_YOUR_PASSWORD
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 5
      minimum-idle: 2
      connection-timeout: 30000

  jpa:
    hibernate:
      ddl-auto: update
    show-sql: false
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect
        format_sql: true

server:
  port: 8080

aws:
  region: us-east-1

  s3:
    bucket-name: $S3_BUCKET
    product-images-prefix: products/
    max-file-size: 5242880

  dynamodb:
    table-name: cloudmart-cart

  sqs:
    order-queue-url: $SQS_URL
    consumer:
      enabled: true
      max-messages: 5

  sns:
    order-topic-arn: $SNS_ARN

  secrets:
    enabled: false

  parameter-store:
    enabled: false

jwt:
  secret: cloudmart-super-secret-jwt-key-change-this-to-something-very-secure-256-bits-minimum
  expiration: 86400000

app:
  cors:
    allowed-origins: http://localhost:3000,http://localhost:5173,http://$EC2_IP:3000,http://$EC2_IP:8080

  swagger:
    servers: http://$EC2_IP:8080,http://localhost:8080

  upload:
    allowed-extensions: jpg,jpeg,png,webp
    max-file-size: 5242880

logging:
  level:
    com.cloudmartbackend: INFO
    com.cloudmartbackend.cloudmart.worker: DEBUG
    org.springframework.web: INFO
    org.hibernate.SQL: INFO
EOF

    echo -e "${GREEN}✅ Generated: application-generated.yml${NC}"
    echo -e "${YELLOW}Don't forget to replace the database password!${NC}"
}

# Purge SQS
purge_sqs() {
    SQS_URL=$(get_terraform_output sqs_queue_url)
    echo -e "${YELLOW}Purging SQS queue...${NC}"
    aws sqs purge-queue --queue-url "$SQS_URL"
    echo -e "${GREEN}✅ Queue purged${NC}"
}

# Main loop
while true; do
    show_menu
    case $choice in
        1) deploy_jar ;;
        2) ssh_connect ;;
        3) view_logs ;;
        4) restart_app ;;
        5) check_status ;;
        6) test_health ;;
        7) show_outputs ;;
        8) generate_app_yml ;;
        9) purge_sqs ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac

    read -p "Press Enter to continue..."
done