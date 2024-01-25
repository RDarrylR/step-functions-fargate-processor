provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

# Get all possible AZs
data "aws_availability_zones" "available_azs" {}

# Setup VPC
resource "aws_vpc" "main_network" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Setup public subnets - one for each az
resource "aws_subnet" "private_subnet" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main_network.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_azs.names[count.index]
  vpc_id            = aws_vpc.main_network.id
  tags = {
    Name = "${var.project_name}-private-subnet-${count.index}"
  }
}

# Setup public subnets - one for each az
resource "aws_subnet" "public_subnet" {
  count                   = var.az_count
  cidr_block              = cidrsubnet(aws_vpc.main_network.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available_azs.names[count.index]
  vpc_id                  = aws_vpc.main_network.id
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet-${count.index}"
  }
}

# Define internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_network.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main_network.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

# Define NAT gateway for each private subnet
resource "aws_eip" "nat_gateway_eip" {
  count      = var.az_count
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "${var.project_name}-nat-gateway-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  count         = var.az_count
  subnet_id     = element(aws_subnet.public_subnet.*.id, count.index)
  allocation_id = element(aws_eip.nat_gateway_eip.*.id, count.index)
  tags = {
    Name = "${var.project_name}-nat-gateway-${count.index}"
  }
}

# Create route table for each private subnet
resource "aws_route_table" "private_route_table" {
  count  = var.az_count
  vpc_id = aws_vpc.main_network.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.nat_gateway.*.id, count.index)
  }

  tags = {
    Name = "${var.project_name}-NAT-Gateway-rt-${count.index}"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main_network.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Associate route tables with private subnets
resource "aws_route_table_association" "private_route_table_association" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = element(aws_route_table.private_route_table.*.id, count.index)
}

# VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main_network.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

# Associate VPC endpoint for S3 with private route tables
resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_rt_association" {
  count           = var.az_count
  route_table_id  = element(aws_route_table.private_route_table.*.id, count.index)
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

# Define Log Group
resource "aws_cloudwatch_log_group" "log_group" {
  name = "/ecs/${var.project_name}"

  tags = {
    Name = "${var.task_container_name}"
  }
}

# Define Log stream
resource "aws_cloudwatch_log_stream" "log_stream" {
  name           = "${var.project_name}-log-stream"
  log_group_name = aws_cloudwatch_log_group.log_group.name
}

# Make sure S3 bucket name is globally unique
resource "random_string" "s3_bucket_randomness" {
  length  = 12
  upper   = false
  lower   = true
  special = false
}

# Store the step function ARN in SSM Param store for the lambda function to get
resource "aws_ssm_parameter" "step_function_arn" {
  name  = "/config/step_function_arn"
  type  = "String"
  value = aws_sfn_state_machine.sfn_state_machine.arn
}

# S3 bucket for incoming sales data
resource "aws_s3_bucket" "bucket" {
  bucket = "${var.project_name}-${random_string.s3_bucket_randomness.result}"
}

# An auth config in eventbridge is required to call HTTP endpoints from Step Functions
# (Even if the HTTP endpoint doesn't require auth)
resource "aws_cloudwatch_event_connection" "slack_webhook" {
  name               = "slack-webhook-notification-conn"
  description        = "slack-webhook-notification-conn"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "dummy"
      value = "value"
    }
  }
}
