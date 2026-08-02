#!/bin/bash

# =============================================================================
# BIA - Script de Deploy e Rollback no ECS
# Gerado por: Kiro (DevOps Engineer - Projeto BIA)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configurações
# -----------------------------------------------------------------------------
REGIAO="us-east-1"
NOME_REPOSITORIO_ECR="bia"

# Recursos por ambiente
CLUSTER_SEM_ALB="bia"
SERVICE_SEM_ALB="task-def-bia-service-1u61p55z"
TASK_DEF_SEM_ALB="task-def-bia"

CLUSTER_COM_ALB="cluster-bia-alb"
SERVICE_COM_ALB="service-bia-alb"
TASK_DEF_COM_ALB="task-def-bia-alb"

# Variáveis globais preenchidas conforme escolha do ambiente
# (inicializadas com valor padrão para evitar erro com nounset)
CLUSTER="${CLUSTER:-}"
SERVICE="${SERVICE:-}"
TASK_DEF="${TASK_DEF:-}"

# -----------------------------------------------------------------------------
# Cores para output
# -----------------------------------------------------------------------------
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
CIANO='\033[0;36m'
NEGRITO='\033[1m'
RESET='\033[0m'

# -----------------------------------------------------------------------------
# Funções utilitárias
# -----------------------------------------------------------------------------

log_info()    { echo -e "${CIANO}[INFO]${RESET} $1"; }
log_ok()      { echo -e "${VERDE}[OK]${RESET}   $1"; }
log_aviso()   { echo -e "${AMARELO}[AVISO]${RESET} $1"; }
log_erro()    { echo -e "${VERMELHO}[ERRO]${RESET}  $1"; }

separador() {
  echo -e "${CIANO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

cabecalho() {
  clear
  separador
  echo -e "${NEGRITO}${CIANO}  BIA — Deploy & Rollback ECS${RESET}"
  separador
  echo ""
}

verificar_dependencias() {
  log_info "Verificando dependências..."

  if ! command -v docker &>/dev/null; then
    log_erro "Docker não encontrado. Instale o Docker e tente novamente."
    exit 1
  fi

  if ! docker info &>/dev/null; then
    log_erro "Docker não está rodando. Inicie o serviço e tente novamente."
    exit 1
  fi

  if ! command -v aws &>/dev/null; then
    log_erro "AWS CLI não encontrada. Instale e configure e tente novamente."
    exit 1
  fi

  if [ ! -f "Dockerfile" ]; then
    log_erro "Dockerfile não encontrado no diretório atual: $(pwd)"
    log_erro "Execute este script a partir da raiz do projeto BIA."
    exit 1
  fi

  log_ok "Todas as dependências estão disponíveis."
}

buscar_uri_ecr() {
  log_info "Buscando URI do repositório ECR '${NOME_REPOSITORIO_ECR}'..."

  URI_ECR=$(aws ecr describe-repositories \
    --repository-names "${NOME_REPOSITORIO_ECR}" \
    --region "${REGIAO}" \
    --query "repositories[0].repositoryUri" \
    --output text 2>/dev/null)

  if [ -z "${URI_ECR}" ] || [ "${URI_ECR}" == "None" ]; then
    log_erro "Repositório ECR '${NOME_REPOSITORIO_ECR}' não encontrado na região ${REGIAO}."
    exit 1
  fi

  log_ok "URI ECR: ${URI_ECR}"
}

login_ecr() {
  log_info "Autenticando no ECR..."

  ACCOUNT_ID=$(aws sts get-caller-identity \
    --query "Account" \
    --output text \
    --region "${REGIAO}")

  aws ecr get-login-password --region "${REGIAO}" | \
    docker login --username AWS --password-stdin \
    "${ACCOUNT_ID}.dkr.ecr.${REGIAO}.amazonaws.com" &>/dev/null

  log_ok "Autenticação no ECR realizada com sucesso."
}

aguardar_deploy() {
  log_info "Aguardando estabilização do serviço (isso pode levar alguns minutos)..."

  aws ecs wait services-stable \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --region "${REGIAO}"

  log_ok "Serviço estabilizado com sucesso!"
}

# -----------------------------------------------------------------------------
# Menu: Escolha de Ambiente
# -----------------------------------------------------------------------------

menu_ambiente() {
  echo -e "${NEGRITO}Selecione o ambiente:${RESET}"
  echo ""
  echo "  1) Sem ALB   →  cluster: ${CLUSTER_SEM_ALB} | service: ${SERVICE_SEM_ALB} | task-def: ${TASK_DEF_SEM_ALB}"
  echo "  2) Com ALB   →  cluster: ${CLUSTER_COM_ALB} | service: ${SERVICE_COM_ALB} | task-def: ${TASK_DEF_COM_ALB}"
  echo ""
  read -rp "Opção [1/2]: " opcao_ambiente

  case "${opcao_ambiente}" in
    1)
      CLUSTER="${CLUSTER_SEM_ALB}"
      SERVICE="${SERVICE_SEM_ALB}"
      TASK_DEF="${TASK_DEF_SEM_ALB}"
      log_ok "Ambiente selecionado: ${NEGRITO}Sem ALB${RESET}"
      ;;
    2)
      CLUSTER="${CLUSTER_COM_ALB}"
      SERVICE="${SERVICE_COM_ALB}"
      TASK_DEF="${TASK_DEF_COM_ALB}"
      log_ok "Ambiente selecionado: ${NEGRITO}Com ALB${RESET}"
      ;;
    *)
      log_erro "Opção inválida."
      exit 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Deploy
# -----------------------------------------------------------------------------

executar_deploy() {
  echo ""
  separador
  echo -e "${NEGRITO}  DEPLOY${RESET}"
  separador
  echo ""

  # Solicita o short commit hash
  read -rp "Informe o short commit hash do Git (ex: a3f1c2b): " COMMIT_HASH

  if [ -z "${COMMIT_HASH}" ]; then
    log_erro "Commit hash não pode ser vazio."
    exit 1
  fi

  # Validação básica: apenas caracteres hexadecimais
  if ! echo "${COMMIT_HASH}" | grep -qE '^[0-9a-f]{6,40}$'; then
    log_erro "Formato inválido. Use apenas caracteres hexadecimais (ex: a3f1c2b)."
    exit 1
  fi

  buscar_uri_ecr
  login_ecr

  TAG_IMAGEM="${URI_ECR}:${COMMIT_HASH}"

  # Build da imagem
  echo ""
  log_info "Iniciando build da imagem Docker..."
  log_info "Tag: ${TAG_IMAGEM}"
  echo ""

  docker build -t "${TAG_IMAGEM}" .

  log_ok "Build concluído."

  # Push para o ECR
  echo ""
  log_info "Enviando imagem para o ECR..."

  docker push "${TAG_IMAGEM}"

  log_ok "Imagem enviada: ${TAG_IMAGEM}"

  # Busca a task definition ativa
  echo ""
  log_info "Buscando task definition ativa: ${TASK_DEF}..."

  TASK_DEF_JSON=$(aws ecs describe-task-definition \
    --task-definition "${TASK_DEF}" \
    --region "${REGIAO}" \
    --query "taskDefinition" \
    --output json)

  # Registra nova revisão com a nova imagem
  log_info "Registrando nova revisão da task definition com a nova imagem..."

  NOVA_TASK_DEF=$(echo "${TASK_DEF_JSON}" | \
    python3 -c "
import json, sys

td = json.load(sys.stdin)
nova_imagem = '${TAG_IMAGEM}'

# Atualiza a imagem no primeiro container
td['containerDefinitions'][0]['image'] = nova_imagem

# Remove campos que não podem ser enviados no registro
for campo in ['taskDefinitionArn', 'revision', 'status', 'requiresAttributes',
              'compatibilities', 'registeredAt', 'registeredBy', 'deregisteredAt']:
    td.pop(campo, None)

print(json.dumps(td))
")

  NOVA_REVISAO_ARN=$(aws ecs register-task-definition \
    --cli-input-json "${NOVA_TASK_DEF}" \
    --region "${REGIAO}" \
    --query "taskDefinition.taskDefinitionArn" \
    --output text)

  NUMERO_REVISAO=$(echo "${NOVA_REVISAO_ARN}" | awk -F: '{print $NF}')

  log_ok "Nova revisão registrada: ${TASK_DEF}:${NUMERO_REVISAO}"

  # Atualiza o serviço ECS
  echo ""
  log_info "Atualizando serviço ECS '${SERVICE}' no cluster '${CLUSTER}'..."

  aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --task-definition "${NOVA_REVISAO_ARN}" \
    --region "${REGIAO}" \
    --output text \
    --query "service.serviceArn" > /dev/null

  log_ok "Serviço atualizado para a revisão ${NUMERO_REVISAO}."

  # Aguarda estabilização
  echo ""
  aguardar_deploy

  echo ""
  separador
  echo -e "${VERDE}${NEGRITO}  Deploy concluído com sucesso!${RESET}"
  echo -e "  Imagem  : ${TAG_IMAGEM}"
  echo -e "  Revisão : ${TASK_DEF}:${NUMERO_REVISAO}"
  echo -e "  Serviço : ${SERVICE} @ ${CLUSTER}"
  separador
}

# -----------------------------------------------------------------------------
# Rollback
# -----------------------------------------------------------------------------

executar_rollback() {
  echo ""
  separador
  echo -e "${NEGRITO}  ROLLBACK${RESET}"
  separador
  echo ""

  # Lista todas as revisões ativas da task definition
  log_info "Buscando revisões ativas de '${TASK_DEF}'..."
  echo ""

  REVISOES=$(aws ecs list-task-definitions \
    --family-prefix "${TASK_DEF}" \
    --status ACTIVE \
    --sort DESC \
    --region "${REGIAO}" \
    --query "taskDefinitionArns[]" \
    --output json)

  TOTAL=$(echo "${REVISOES}" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

  if [ "${TOTAL}" -eq 0 ]; then
    log_erro "Nenhuma revisão ativa encontrada para '${TASK_DEF}'."
    exit 1
  fi

  # Exibe a tabela de revisões
  printf "  %-5s %-12s %-35s %-30s\n" "NUM" "REVISÃO" "IMAGEM (TAG)" "DATA DE REGISTRO"
  separador

  echo "${REVISOES}" | python3 -c "
import json, sys, subprocess, re

arns = json.load(sys.stdin)

for arn in arns:
    revisao_num = arn.split(':')[-1]
    familia = arn.split('/')[-1].rsplit(':', 1)[0]

    result = subprocess.run(
        ['aws', 'ecs', 'describe-task-definition',
         '--task-definition', arn,
         '--region', '${REGIAO}',
         '--query', 'taskDefinition',
         '--output', 'json'],
        capture_output=True, text=True
    )

    td = json.loads(result.stdout)
    imagem = td['containerDefinitions'][0].get('image', 'N/A')
    tag = imagem.split(':')[-1] if ':' in imagem else imagem
    data = td.get('registeredAt', 'N/A')

    # Formata a data (remove microsegundos e timezone verbose)
    data_fmt = re.sub(r'\.\d+\+.*', '', data).replace('T', ' ')

    # Trunca tag se muito longa
    tag_fmt = (tag[:32] + '..') if len(tag) > 34 else tag

    print(f'  {revisao_num:<5} {revisao_num:<12} {tag_fmt:<35} {data_fmt:<30}')
"

  echo ""
  separador

  # Solicita a revisão desejada
  read -rp "Informe o número da revisão para rollback: " REVISAO_ESCOLHIDA

  if ! echo "${REVISAO_ESCOLHIDA}" | grep -qE '^[0-9]+$'; then
    log_erro "Revisão inválida. Informe apenas o número."
    exit 1
  fi

  TASK_DEF_ARN_ROLLBACK="${TASK_DEF}:${REVISAO_ESCOLHIDA}"

  # Confirma se a revisão escolhida existe na lista
  REVISAO_VALIDA=$(echo "${REVISOES}" | python3 -c "
import json, sys
arns = json.load(sys.stdin)
escolhida = '${REVISAO_ESCOLHIDA}'
valido = any(arn.endswith(':' + escolhida) for arn in arns)
print('sim' if valido else 'nao')
")

  if [ "${REVISAO_VALIDA}" != "sim" ]; then
    log_erro "Revisão ${REVISAO_ESCOLHIDA} não encontrada ou não está ativa."
    exit 1
  fi

  # Confirmação antes de executar
  echo ""
  log_aviso "Você está prestes a fazer rollback para: ${NEGRITO}${TASK_DEF_ARN_ROLLBACK}${RESET}"
  log_aviso "Serviço: ${SERVICE} @ ${CLUSTER}"
  echo ""
  read -rp "Confirma o rollback? [s/N]: " CONFIRMACAO

  if [[ ! "${CONFIRMACAO}" =~ ^[sS]$ ]]; then
    log_info "Rollback cancelado pelo usuário."
    exit 0
  fi

  # Executa o rollback
  echo ""
  log_info "Aplicando rollback para ${TASK_DEF_ARN_ROLLBACK}..."

  aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --task-definition "${TASK_DEF_ARN_ROLLBACK}" \
    --region "${REGIAO}" \
    --output text \
    --query "service.serviceArn" > /dev/null

  log_ok "Serviço atualizado para a revisão ${REVISAO_ESCOLHIDA}."

  # Aguarda estabilização
  echo ""
  aguardar_deploy

  echo ""
  separador
  echo -e "${VERDE}${NEGRITO}  Rollback concluído com sucesso!${RESET}"
  echo -e "  Task Def: ${TASK_DEF_ARN_ROLLBACK}"
  echo -e "  Serviço : ${SERVICE} @ ${CLUSTER}"
  separador
}

# -----------------------------------------------------------------------------
# Menu Principal
# -----------------------------------------------------------------------------

menu_principal() {
  echo -e "${NEGRITO}O que deseja fazer?${RESET}"
  echo ""
  echo "  1) Deploy   — build + push ECR + atualizar ECS"
  echo "  2) Rollback — escolher revisão anterior da task definition"
  echo "  0) Sair"
  echo ""
  read -rp "Opção [0/1/2]: " opcao_acao

  case "${opcao_acao}" in
    1) echo ""; menu_ambiente; executar_deploy ;;
    2) echo ""; menu_ambiente; executar_rollback ;;
    0) log_info "Saindo..."; exit 0 ;;
    *) log_erro "Opção inválida."; exit 1 ;;
  esac
}

# -----------------------------------------------------------------------------
# Execução principal
# -----------------------------------------------------------------------------

# Garante que o script está sendo executado da raiz do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

cabecalho
verificar_dependencias
echo ""
menu_principal
