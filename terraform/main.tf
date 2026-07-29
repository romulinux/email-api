terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configuração do provider
provider "aws" {
  region = "us-east-1" # Região padrão para SES, pode ser alterada conforme a necessidade
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==========================================
# 1. SQS Queue
# ==========================================
resource "aws_sqs_queue" "email_queue" {
  name                       = "email-queue"
  visibility_timeout_seconds = 30 # Tempo que o Lambda tem para processar antes de voltar para a fila
}

# ==========================================
# 2. IAM & Lambda Function
# ==========================================

# Role do Lambda
resource "aws_iam_role" "lambda_role" {
  name = "email_lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Permissões do Lambda (Ler SQS + Gravar Logs)
resource "aws_iam_role_policy_attachment" "lambda_sqs_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# Permissões do Lambda (Enviar e-mail via SES)
resource "aws_iam_policy" "lambda_ses_policy" {
  name = "lambda_ses_send_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = ["ses:SendEmail", "ses:SendRawEmail"],
      Effect   = "Allow",
      Resource = "*" 
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ses_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ses_policy.arn
}

# Código fonte temporário (zip) para o Lambda provisionar com sucesso
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"
  source {
    content  = "// Substitua este arquivo pelo seu código Node.js real de envio do SES\nexport const handler = async (event) => { console.log(event); return 'ok'; };"
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "email_sender" {
  function_name    = "email_sender_worker"
  role             = aws_iam_role.lambda_role.arn
  handler          = "routes/email/enviar.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# Trigger do SQS para o Lambda
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.email_queue.arn
  function_name    = aws_lambda_function.email_sender.arn
  batch_size       = 10
}

# ==========================================
# 3. IAM do API Gateway (Permissão de enviar pro SQS)
# ==========================================
resource "aws_iam_role" "apigw_sqs_role" {
  name = "apigateway_sqs_integration_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "apigw_sqs_policy" {
  name = "apigateway_sqs_policy"
  role = aws_iam_role.apigw_sqs_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "sqs:SendMessage",
      Effect   = "Allow",
      Resource = aws_sqs_queue.email_queue.arn
    }]
  })
}

# ==========================================
# 4. API Gateway: Resources & Model
# ==========================================
resource "aws_api_gateway_rest_api" "email_api" {
  name = "EmailServiceAPI"
}

# Rotas: /api /v1 /email /enviar
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  parent_id   = aws_api_gateway_rest_api.email_api.root_resource_id
  path_part   = "api"
}
resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "v1"
}
resource "aws_api_gateway_resource" "email" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "email"
}
resource "aws_api_gateway_resource" "enviar" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  parent_id   = aws_api_gateway_resource.email.id
  path_part   = "enviar"
}

# Model de validação (JSON Schema) que gera o HTTP 400 automaticamente
resource "aws_api_gateway_model" "email_model" {
  rest_api_id  = aws_api_gateway_rest_api.email_api.id
  name         = "EmailBodyModel"
  content_type = "application/json"
  schema = jsonencode({
    type = "object",
    required = ["remetente", "destinatario", "assunto", "mensagem"],
    properties = {
      remetente = {
        type = "object",
        required = ["email", "nome"],
        properties = {
          email = { type = "string" },
          nome  = { type = "string" }
        }
      },
      destinatario = {
        type = "object",
        required = ["email", "nome"],
        properties = {
          email = { type = "string" },
          nome  = { type = "string" }
        }
      },
      assunto  = { type = "string" },
      mensagem = { type = "string" }
    }
  })
}

# Validador de corpo
resource "aws_api_gateway_request_validator" "body_validator" {
  name                        = "validate-body-only"
  rest_api_id                 = aws_api_gateway_rest_api.email_api.id
  validate_request_body       = true
  validate_request_parameters = false
}

# ==========================================
# 5. API Gateway: Method & Integration (VTL)
# ==========================================
resource "aws_api_gateway_method" "post_enviar" {
  rest_api_id   = aws_api_gateway_rest_api.email_api.id
  resource_id   = aws_api_gateway_resource.enviar.id
  http_method   = "POST"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.body_validator.id
  request_models = {
    "application/json" = aws_api_gateway_model.email_model.name
  }
}

resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.email_api.id
  resource_id             = aws_api_gateway_resource.enviar.id
  http_method             = aws_api_gateway_method.post_enviar.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.apigw_sqs_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.email_queue.name}"

  # Força o content-type exigido pela API do SQS
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  # Mapping Template (VTL) transforma o corpo JSON para urlencoded 
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

# Resposta HTTP 200 Padrão
resource "aws_api_gateway_method_response" "resp_200" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  resource_id = aws_api_gateway_resource.enviar.id
  http_method = aws_api_gateway_method.post_enviar.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "sqs_200" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  resource_id = aws_api_gateway_resource.enviar.id
  http_method = aws_api_gateway_method.post_enviar.http_method
  status_code = aws_api_gateway_method_response.resp_200.status_code

  depends_on = [
    aws_api_gateway_integration.sqs_integration
  ]

  # O SQS retorna XML no status 200, então sobrescrevemos retornando um JSON limpo
  response_templates = {
    "application/json" = "{\"mensagem\": \"E-mail recebido e enfileirado para envio.\"}"
  }
}

# ==========================================
# 6. Deploy & Rate Limiting (Usage Plan)
# ==========================================
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.email_api.id
  
  # Força o deploy após a configuração do método e da integração
  depends_on = [
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration_response.sqs_200
  ]
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.email_api.id
  stage_name    = "prod"
}

# Rate Limit da API
resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name = "EmailApiUsagePlan"

  api_stages {
    api_id = aws_api_gateway_rest_api.email_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit  = 10  # 10 requisições por segundo
    burst_limit = 20  # Pico de até 20 requisições
  }
}

# URL de saída para facilitar os testes
output "api_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/api/v1/email/enviar"
}