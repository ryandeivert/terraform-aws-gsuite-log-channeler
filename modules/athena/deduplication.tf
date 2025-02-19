
locals {
  function_name     = "${var.prefix}-gsuite-admin-reports-deduplication"
  metrics_namespace = "gsuite-logs-channeler"
}

resource "aws_cloudwatch_log_group" "deduplication_lambda" {
  count             = var.deduplication.enabled == true ? 1 : 0
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.deduplication.lambda.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume_role" {
  count = var.deduplication.enabled == true ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deduplication" {
  count              = var.deduplication.enabled == true ? 1 : 0
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role[0].json
}

resource "aws_lambda_function" "deduplication" {
  count            = var.deduplication.enabled == true ? 1 : 0
  function_name    = local.function_name
  handler          = "main.handler"
  memory_size      = var.deduplication.lambda.memory
  publish          = true
  role             = aws_iam_role.deduplication[0].arn
  runtime          = "python3.12"
  timeout          = min(var.deduplication.lambda.timeout, 300) # max timeout of 5 min for firehose data transformation
  filename         = data.archive_file.deduplication[0].output_path
  source_code_hash = data.archive_file.deduplication[0].output_base64sha256

  layers = [
    coalesce(
      var.deduplication.lambda.aws_lambda_powertools_layer_arn,
      # Default to public Lambda layer corresponding to semantic version v2.41.0 of aws-lambda-powertools
      # Reference: https://docs.powertools.aws.dev/lambda/python/2.41.0/#lambda-layer
      "arn:aws:lambda:${local.region}:017000801446:layer:AWSLambdaPowertoolsPythonV2:76"
    )
  ]

  environment {
    variables = {
      PREFIX                       = var.prefix
      LOG_LEVEL                    = var.deduplication.lambda.log_level
      POWERTOOLS_METRICS_NAMESPACE = local.metrics_namespace
    }
  }
}

resource "aws_lambda_alias" "deduplication" {
  count            = var.deduplication.enabled == true ? 1 : 0
  description      = "production alias for ${aws_lambda_function.deduplication[0].function_name}"
  function_name    = aws_lambda_function.deduplication[0].function_name
  function_version = aws_lambda_function.deduplication[0].version
  name             = "production"
}

data "archive_file" "deduplication" {
  count       = var.deduplication.enabled == true ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/functions/deduplication"
  output_path = "${path.module}/builds/deduplication.zip"
}

data "aws_iam_policy_document" "deduplication" {
  count = var.deduplication.enabled == true ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.deduplication_lambda[0].arn}:*",
      "${aws_cloudwatch_log_group.deduplication_lambda[0].arn}:*:*",
    ]
  }
}

resource "aws_iam_role_policy" "deduplication" {
  count  = var.deduplication.enabled == true ? 1 : 0
  name   = "DefaultPolicy"
  role   = aws_iam_role.deduplication[0].name
  policy = data.aws_iam_policy_document.deduplication[0].json
}
