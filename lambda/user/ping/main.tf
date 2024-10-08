locals {
  project         = "demo"
  module          = "user"
  function        = "ping"
  module_function = "${local.module}/${local.function}"
  src_path        = "./lambda/${local.module_function}"
  binary_path     = "./bin/${local.module_function}/bootstrap"
  archive_path    = "./bin/${local.module_function}/${local.function}.zip"
}

resource "null_resource" "function_binary" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-trimpath go build -mod=readonly -ldflags='-s -w' -o ${local.binary_path} ${local.src_path}"
  }
}

data "archive_file" "function_archive" {
  depends_on = [null_resource.function_binary]

  type        = "zip"
  source_file = local.binary_path
  output_path = local.archive_path
}

resource "aws_sqs_queue" "user_ping_dead_letter_queue" {
  name                        = "${var.ENV}-${local.project}_${local.module}_${local.function}-DLQ"
  message_retention_seconds   = 60
  visibility_timeout_seconds  = 60
}

resource "aws_sqs_queue" "user_ping_queue" {
  name                      = "${var.ENV}-${local.project}_${local.module}_${local.function}"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
  redrive_policy            = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.user_ping_dead_letter_queue.arn}\",\"maxReceiveCount\":4}"
}

resource "aws_lambda_function" "user_ping" {
  function_name = "${var.ENV}-${local.project}_${local.module}_${local.function}"
  description   = "Lambda for ${local.module} module."
  role          = var.iam_role
  handler       = local.function
  memory_size   = 128

  filename         = local.archive_path
  source_code_hash = data.archive_file.function_archive.output_base64sha256

  runtime = "provided.al2"
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  batch_size        = 1
  event_source_arn  = aws_sqs_queue.user_ping_queue.arn
  enabled           = true
  function_name     = aws_lambda_function.user_ping.arn
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/${aws_lambda_function.user_ping.function_name}"
  retention_in_days = 7
}