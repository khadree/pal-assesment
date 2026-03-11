data "aws_availability_zones" "available" {}

locals {
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
}


//S3 bucket for CodePipeline Artifact
resource "aws_s3_bucket" "bucket" {
  bucket        = "vprofile-artifact-bucket-my-2025"
  force_destroy = true

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}


// ECR repository for application

resource "aws_ecr_repository" "image_repo" {
  name                 = "node-devops-app-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

import {
  to = aws_ecr_repository.image_repo
  id = "node-devops-app-repo"
}


// Application Security Group for the service
resource "aws_security_group" "app_sg" {
  name        = "node-SG"
  description = "Example in default VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//Create the target group to be attached to the load balancer
resource "aws_lb_target_group" "vprofile_TG" {
  name        = "Vprofile-TargetGroup"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    timeout             = 10
    interval            = 60
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  vpc_id = aws_vpc.main.id
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "devops-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.main
  tags   = { Name = "devops-vpc-igw" }
}



# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "dev-vpc-public-${count.index + 1}"

  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "dev-vpc-private-${count.index + 1}"

  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = length(local.azs)
  domain = "vpc"
  tags   = { Name = "dev-vpc-nat-eip-${count.index + 1}" }
}

# NAT Gateways (one per AZ for HA)
resource "aws_nat_gateway" "this" {
  count         = length(local.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "dev-vpc-nat-${count.index + 1}" }
  depends_on    = [aws_internet_gateway.this]
}


# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "dev-vpc-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (one per AZ)
resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }
  tags = { Name = "dev-vpc-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
// Load balancer Security Group
resource "aws_security_group" "alb_sg" {
  name        = "vprofile-ELB"
  description = "Security group for the Load balance"
  vpc_id      = aws_vpc.main.id

  ingress {

    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {

    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

}

// Add listener to the Load Balancer
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.vprofileLB.arn # reference to your ALB
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vprofile_TG.arn
  }
}


//Create the Laod balancer to be attached
resource "aws_lb" "vprofileLB" {
  name               = "VprofileLB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]
}


// Create a cluster
resource "aws_ecs_cluster" "ecs_vprofile" {
  name = "vprofifle-cluster"
}


resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "secrets_access" {
  name = "secrets-manager-access"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.app_secrets.arn
    }]
  })
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name = "prod/secret"
}
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

#Create Log groups
resource "aws_cloudwatch_log_group" "vprofile_log_group" {
  name              = "/ecs/vprofile-log"
  retention_in_days = 1
}


# Create Task Definition
resource "aws_ecs_task_definition" "vprofile" {
  family                   = "vprofile-task"
  network_mode             = "awsvpc"
  cpu                      = "2048"
  memory                   = "4096"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "vprofileContainer"
      image     = "${aws_ecr_repository.image_repo.repository_url}:latest"
      cpu       = 2048
      memory    = 4096
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "POSTGRES_PORT", value = "5432" },
        { name = "REDIS_PORT", value = "6379" },
        { name = "PORT", value = "3000" }
      ]
      secrets = [
        {
          name      = "POSTGRES_PASSWORD"
          valueFrom = "arn:aws:secretsmanager:us-east-1:114725187682:secret:prod/secret-ZSpUkK:POSTGRES_PASSWORD::"
        },
        {
          name      = "POSTGRES_USER"
          valueFrom = "arn:aws:secretsmanager:us-east-1:114725187682:secret:prod/secret-ZSpUkK:POSTGRES_USER::"
        },
        {
          name      = "POSTGRES_HOST"
          valueFrom = "arn:aws:secretsmanager:us-east-1:114725187682:secret:prod/secret-ZSpUkK:POSTGRES_HOST::"
        },
        {
          name      = "POSTGRES_DB"
          valueFrom = "arn:aws:secretsmanager:us-east-1:114725187682:secret:prod/secret-ZSpUkK:POSTGRES_DB::"
        },
        {
          name      = "REDIS_HOST"
          valueFrom = "arn:aws:secretsmanager:us-east-1:114725187682:secret:prod/secret-ZSpUkK:REDIS_HOST::"
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = "arn:aws:secretsmanager:us-east-1:114725187682:secret:prod/secret-ZSpUkK:REDIS_PASSWORD::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/vprofile-log"
          "awslogs-region"        = "eu-west-1"
          "awslogs-stream-prefix" = "vprofile-log"
        }
      }
    }
  ])
}



//Create a service for the container
resource "aws_ecs_service" "vprofile" {
  name            = "vprofile_service"
  cluster         = aws_ecs_cluster.ecs_vprofile.id
  task_definition = aws_ecs_task_definition.vprofile.arn
  desired_count   = 0
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 30

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.app_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.vprofile_TG.arn
    container_name   = "vprofileContainer"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.listener]
}



#### Attach s3 to code build for artifact
# resource "aws_iam_role_policy" "codebuild_s3_policy" {
#   role = aws_iam_role.codebuild_role.name

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:GetObjectVersion",
#           "s3:PutObject"
#         ]
#         Resource = "arn:aws:s3:::vprofile-artifact-bucket-my-2025/*"
#       }
#     ]
#   })
# }
