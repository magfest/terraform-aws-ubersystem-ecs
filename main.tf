terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.38.0"
    }
  }
}


# -------------------------------------------------------------------
# Import Data block for AWS information
# -------------------------------------------------------------------

data "aws_ecs_cluster" "ecs" {
  cluster_name = var.ecs_cluster
}


# -------------------------------------------------------------------
# MAGFest Ubersystem Load Balancer
# -------------------------------------------------------------------

# data "aws_lb" "elb" {
#   arn  = var.lb_arn
# }

resource "aws_lb_target_group" "ubersystem_web" {
  name_prefix   = "uber"
  port          = 80
  protocol      = "HTTP"
  vpc_id        = var.vpc_id
}

# -------------------------------------------------------------------
# MAGFest Ubersystem Containers
# -------------------------------------------------------------------

resource "aws_ecs_service" "ubersystem_web" {
  name            = "ubersystem_web"
  cluster         = data.aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.ubersystem_web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.ubersystem_web.arn
    container_name   = "web"
    container_port   = 8282
  }
}

resource "aws_ecs_task_definition" "ubersystem_web" {
  family                    = "ubersystem"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "name": "web",
    "image": "bitbyt3r/ubersystem:latest",
    "cpu": 1024,
    "memory": 2048,
    "essential": true
  }
]
TASK_DEFINITION

  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"

  volume {
    name = "static-files"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.ubersystem_static.id
      root_directory          = "/"
      # transit_encryption      = "ENABLED"
      # transit_encryption_port = 2999
      # authorization_config {
      #   access_point_id = aws_efs_access_point.test.id
      #   iam             = "ENABLED"
      # }
    }
  }
}

# -------------------------------------------------------------------
# MAGFest Ubersystem Supporting Services (RabbitMQ)
# -------------------------------------------------------------------

# resource "aws_ecs_service" "rabbitmq" {
  
# }

# resource "aws_ecs_task_definition" "rabbitmq" {
#   family                = "rabbitmq"
#   container_definitions = file("task-definitions/rabbitmq.json")
# }

# -------------------------------------------------------------------
# MAGFest Ubersystem Supporting Services (Redis)
# -------------------------------------------------------------------

# resource "aws_ecs_service" "redis" {
  
# }

# resource "aws_ecs_task_definition" "redis" {
#   family                = "redis"
#   container_definitions = file("task-definitions/redis.json")
# }

# -------------------------------------------------------------------
# MAGFest Ubersystem Shared File Directory
# -------------------------------------------------------------------

resource "aws_efs_file_system" "ubersystem_static" {
  creation_token = "ubersystem"

  tags = {
    Name = "MyProduct"
  }
}
