resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "Process-Store-Data-Daily-State-Machine"
  role_arn = aws_iam_role.step_function_role.arn

  definition = data.template_file.template_step_function_definitions.rendered

}

data "template_file" "template_step_function_definitions" {
  template = file("step-function.tpl")

  vars = {
    connection_notif_arn = "${aws_cloudwatch_event_connection.slack_webhook.arn}"
    slack_webhook        = "${var.slack_webhook}"
    ecs_cluster          = "${aws_ecs_cluster.ecs_cluster.arn}"
    task_def_name        = "${var.task_definition_name}"
    vpc_default_sg       = "${aws_default_security_group.default.id}"
    fargate_subnet       = "${aws_subnet.private_subnet[0].id}"
  }
}


# Set policy for step function
resource "aws_iam_policy" "step_function_policy" {
  name = "step_function_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetBucket*",
          "s3:GetObject*",
          "s3:List*",
          "states:StartExecution",
          "states:InvokeHTTPEndpoint",
          "events:RetrieveConnectionCredentials",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "ecs:RunTask",
          "iam:PassRole"
        ]
        Effect   = "Allow"
        Resource = "*"
      }

    ]
  })
}

# Set exection role for step function
resource "aws_iam_role" "step_function_role" {
  name = "${var.project_name}-step-function-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "states.amazonaws.com"
          }
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "step_functions_policy_attachment" {
  policy_arn = aws_iam_policy.step_function_policy.arn
  role       = aws_iam_role.step_function_role.name
}
