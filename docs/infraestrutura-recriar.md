# Infraestrutura BIA — Passo a Passo para Recriar

> Documento gerado em 2026-08-03. Contém todos os comandos AWS CLI necessários para recriar a infraestrutura do projeto BIA do zero.

---

## Visão Geral da Arquitetura

```
Internet
   │
   ▼
[ALB bia-alb] (internet-facing, HTTP:80 + HTTPS:443)
   │
   ├── HTTP :80  → tg-bia-dev  (default)
   └── HTTPS :443
         ├── rule: host=dev.bia-formacaoaws.abrdns.com → tg-bia-dev
         └── default → tg-bia
              │
              ├── tg-bia     → service-bia-alb     → task-def-bia-alb:5
              └── tg-bia-dev → service-bia-alb-dev → task-def-bia-alb-dev:1
                       │
                       └── [cluster-bia-alb]
                               ├── EC2 i-0d554583fa06d0cf5 (us-east-1a, bia-ec2)
                               └── EC2 i-0406641addf2963fc (us-east-1b, bia-ec2)
                                        │
                                        ▼
                               [RDS bia — PostgreSQL 18.3]
```

---

## Dados Fixos da Conta

| Recurso | Valor |
|---|---|
| Account ID | `332677055960` |
| Região | `us-east-1` |
| VPC | `vpc-02bca9c164cc187f6` |
| Subnet us-east-1a | `subnet-0290a4beb45d1db15` |
| Subnet us-east-1b | `subnet-062aa8d39c7b00f99` |
| Security Group ALB (`bia-alb`) | `sg-01877114bc6042047` |
| Security Group EC2 (`bia-ec2`) | `sg-0b0451168e18ec9a6` |
| Security Group RDS (`bia-db`) | `sg-0ec7f4bbf2d1fb465` |
| Certificate ARN (ACM) | `arn:aws:acm:us-east-1:332677055960:certificate/2d00a6ad-a1a0-437a-a12c-0635a1039f8c` |
| ECR Image | `332677055960.dkr.ecr.us-east-1.amazonaws.com/bia:77f5975` |
| ECS Task Execution Role | `arn:aws:iam::332677055960:role/ecsTaskExecutionRole` |

---

## Passo 1 — Iniciar o RDS (se estiver parado)

O banco de dados RDS foi parado para economizar. Para reativar:

```bash
aws rds start-db-instance \
  --region us-east-1 \
  --db-instance-identifier bia
```

Aguardar ficar `available` (pode levar alguns minutos):

```bash
aws rds describe-db-instances \
  --region us-east-1 \
  --db-instance-identifier bia \
  --query "DBInstances[0].DBInstanceStatus"
```

**Dados do RDS:**
| Campo | Valor |
|---|---|
| Identifier | `bia` |
| Engine | PostgreSQL 18.3 |
| Classe | `db.t3.micro` |
| Endpoint | `bia.cohcuumeu0be.us-east-1.rds.amazonaws.com` |
| Porta | `5432` |
| Usuário | `postgres` |
| Senha | `YEojgjWlCKuOQSBWg3pN` |
| AZ | `us-east-1a` |
| Storage | 20 GB gp2 |
| Multi-AZ | Não |
| Publicly Accessible | Não |
| Security Group | `sg-0ec7f4bbf2d1fb465` (bia-db) |

---

## Passo 2 — Criar os Target Groups

### 2.1 — tg-bia (produção)

```bash
aws elbv2 create-target-group \
  --region us-east-1 \
  --name tg-bia \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-02bca9c164cc187f6 \
  --health-check-protocol HTTP \
  --health-check-port traffic-port \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 5 \
  --unhealthy-threshold-count 2 \
  --matcher HttpCode=200 \
  --target-type instance \
  --ip-address-type ipv4
```

### 2.2 — tg-bia-dev (desenvolvimento)

```bash
aws elbv2 create-target-group \
  --region us-east-1 \
  --name tg-bia-dev \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-02bca9c164cc187f6 \
  --health-check-protocol HTTP \
  --health-check-port traffic-port \
  --health-check-path "/api/versao" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --matcher HttpCode=200 \
  --target-type instance \
  --ip-address-type ipv4
```

> **Anote os ARNs dos dois TGs** retornados nos comandos acima. Você vai precisar deles nos próximos passos.

---

## Passo 3 — Criar o Application Load Balancer

```bash
aws elbv2 create-load-balancer \
  --region us-east-1 \
  --name bia-alb \
  --type application \
  --scheme internet-facing \
  --ip-address-type ipv4 \
  --subnets subnet-0290a4beb45d1db15 subnet-062aa8d39c7b00f99 \
  --security-groups sg-01877114bc6042047
```

> **Anote o ARN do ALB** retornado. Você vai precisar dele para criar os listeners.

---

## Passo 4 — Criar os Listeners do ALB

### 4.1 — Listener HTTP :80 → tg-bia-dev (default)

```bash
aws elbv2 create-listener \
  --region us-east-1 \
  --load-balancer-arn <ARN_DO_ALB> \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=<ARN_TG_BIA_DEV>
```

### 4.2 — Listener HTTPS :443 → tg-bia (default)

```bash
aws elbv2 create-listener \
  --region us-east-1 \
  --load-balancer-arn <ARN_DO_ALB> \
  --protocol HTTPS \
  --port 443 \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09 \
  --certificates CertificateArn=arn:aws:acm:us-east-1:332677055960:certificate/2d00a6ad-a1a0-437a-a12c-0635a1039f8c \
  --default-actions Type=forward,TargetGroupArn=<ARN_TG_BIA>
```

> **Anote o ARN do listener HTTPS.** Você vai precisar para criar a rule de dev.

### 4.3 — Rule HTTPS: host dev.bia-formacaoaws.abrdns.com → tg-bia-dev

```bash
aws elbv2 create-rule \
  --region us-east-1 \
  --listener-arn <ARN_LISTENER_HTTPS> \
  --priority 10 \
  --conditions Field=host-header,Values=dev.bia-formacaoaws.abrdns.com \
  --actions Type=forward,TargetGroupArn=<ARN_TG_BIA_DEV>
```

---

## Passo 5 — Criar o ECS Cluster

```bash
aws ecs create-cluster \
  --region us-east-1 \
  --cluster-name cluster-bia-alb
```

> O cluster foi originalmente criado via **CloudFormation** com Auto Scaling Group e capacity provider. Para recriar de forma equivalente, use o console AWS ou o comando abaixo que recria o cluster simples para uso com EC2 já existente.

---

## Passo 6 — Registrar as EC2 no Cluster ECS

As instâncias EC2 do cluster precisam ter o **ECS Agent** configurado com o nome do cluster. Nas instâncias com tag `ECS Instance - cluster-bia-alb`, o agente já aponta para `cluster-bia-alb`.

Se precisar registrar manualmente, edite `/etc/ecs/ecs.config` nas instâncias:

```bash
echo "ECS_CLUSTER=cluster-bia-alb" >> /etc/ecs/ecs.config
sudo systemctl restart ecs
```

---

## Passo 7 — Criar as Task Definitions

### 7.1 — task-def-bia-alb (revisão 5 — produção)

```bash
aws ecs register-task-definition \
  --region us-east-1 \
  --family task-def-bia-alb \
  --network-mode bridge \
  --requires-compatibilities EC2 \
  --execution-role-arn arn:aws:iam::332677055960:role/ecsTaskExecutionRole \
  --container-definitions '[
    {
      "name": "bia",
      "image": "332677055960.dkr.ecr.us-east-1.amazonaws.com/bia:77f5975",
      "cpu": 1024,
      "memory": 3072,
      "memoryReservation": 410,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 0,
          "protocol": "tcp",
          "name": "porta-aleatoria",
          "appProtocol": "http"
        }
      ],
      "environment": [
        {"name": "DB_HOST", "value": "bia.cohcuumeu0be.us-east-1.rds.amazonaws.com"},
        {"name": "DB_PORT", "value": "5432"},
        {"name": "DB_USER", "value": "postgres"},
        {"name": "DB_PWD",  "value": "YEojgjWlCKuOQSBWg3pN"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/task-def-bia-alb",
          "awslogs-create-group": "true",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]'
```

### 7.2 — task-def-bia-alb-dev (revisão 1 — desenvolvimento)

```bash
aws ecs register-task-definition \
  --region us-east-1 \
  --family task-def-bia-alb-dev \
  --network-mode bridge \
  --requires-compatibilities EC2 \
  --execution-role-arn arn:aws:iam::332677055960:role/ecsTaskExecutionRole \
  --container-definitions '[
    {
      "name": "bia",
      "image": "332677055960.dkr.ecr.us-east-1.amazonaws.com/bia:77f5975",
      "cpu": 1024,
      "memory": 3072,
      "memoryReservation": 410,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 0,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "DB_HOST", "value": "bia.cohcuumeu0be.us-east-1.rds.amazonaws.com"},
        {"name": "DB_PORT", "value": "5432"},
        {"name": "DB_USER", "value": "postgres"},
        {"name": "DB_PWD",  "value": "YEojgjWlCKuOQSBWg3pN"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/task-def-bia-alb-dev",
          "awslogs-create-group": "true",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]'
```

---

## Passo 8 — Criar os ECS Services

### 8.1 — service-bia-alb (produção)

```bash
aws ecs create-service \
  --region us-east-1 \
  --cluster cluster-bia-alb \
  --service-name service-bia-alb \
  --task-definition task-def-bia-alb:5 \
  --desired-count 1 \
  --launch-type EC2 \
  --scheduling-strategy REPLICA \
  --deployment-configuration "minimumHealthyPercent=50,maximumPercent=100" \
  --availability-zone-rebalancing DISABLED \
  --load-balancers "targetGroupArn=<ARN_TG_BIA>,containerName=bia,containerPort=8080"
```

### 8.2 — service-bia-alb-dev (desenvolvimento)

```bash
aws ecs create-service \
  --region us-east-1 \
  --cluster cluster-bia-alb \
  --service-name service-bia-alb-dev \
  --task-definition task-def-bia-alb-dev:1 \
  --desired-count 1 \
  --launch-type EC2 \
  --scheduling-strategy REPLICA \
  --deployment-configuration "minimumHealthyPercent=50,maximumPercent=100" \
  --availability-zone-rebalancing DISABLED \
  --load-balancers "targetGroupArn=<ARN_TG_BIA_DEV>,containerName=bia,containerPort=8080"
```

---

## Verificação Final

Após recriar tudo, verifique se os serviços estão healthy:

```bash
# Verificar services ECS
aws ecs describe-services \
  --region us-east-1 \
  --cluster cluster-bia-alb \
  --services service-bia-alb service-bia-alb-dev \
  --query "services[*].{name:serviceName,status:status,running:runningCount,desired:desiredCount}"

# Verificar health dos targets
aws elbv2 describe-target-health \
  --region us-east-1 \
  --target-group-arn <ARN_TG_BIA> \
  --query "TargetHealthDescriptions[*].{id:Target.Id,port:Target.Port,health:TargetHealth.State}"

aws elbv2 describe-target-health \
  --region us-east-1 \
  --target-group-arn <ARN_TG_BIA_DEV> \
  --query "TargetHealthDescriptions[*].{id:Target.Id,port:Target.Port,health:TargetHealth.State}"

# Testar aplicação
curl http://bia-alb-<novo-dns>.us-east-1.elb.amazonaws.com/api/versao
```

---

## Domínios e DNS

| Domínio | Aponta para |
|---|---|
| `dev.bia-formacaoaws.abrdns.com` | DNS do ALB (CNAME) |

Após recriar o ALB, atualize o registro DNS no seu provedor para apontar para o novo DNS do ALB.

---

## Ordem de Destruição (para economizar quando não usar)

1. Deletar ECS services (desiredCount=0 depois force delete)
2. Deletar ECS cluster
3. Deletar listeners do ALB
4. Deletar ALB
5. Deletar Target Groups
6. Parar RDS (`aws rds stop-db-instance --db-instance-identifier bia`)
7. **NÃO deletar:** EC2 instances, Security Groups, VPC, Subnets, Task Definitions, RDS

> Task Definitions são versionadas e não geram custo — mantenha sempre.

---

## Notas Importantes

- O ECS cluster foi criado originalmente via **CloudFormation** com stack `Infra-ECS-Cluster-cluster-bia-alb-ff935a86`. Se a stack ainda existir, o cluster pode ser recriado por ela.
- As EC2 do cluster têm a tag `aws:autoscaling:groupName` indicando que fazem parte de um Auto Scaling Group (`Infra-ECS-Cluster-cluster-bia-alb-ff935a86-ECSAutoScalingGroup-H9tdWFo4Xtfl`).
- O capacity provider do cluster é `Infra-ECS-Cluster-cluster-bia-alb-ff935a86-AsgCapacityProvider-XHxiQUbumvTc` — vinculado ao ASG acima.
