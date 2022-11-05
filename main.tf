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

data "aws_caller_identity" "current" {}


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
# MAGFest Ubersystem Containers (web)
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
  family                    = "ubersystem_web"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "dnsSearchDomains": null,
    "environmentFiles": null,
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "entryPoint": [],
    "portMappings": [
      {
        "hostPort": 8282,
        "protocol": "tcp",
        "containerPort": 8282
      }
    ],
    "command": [],
    "linuxParameters": null,
    "cpu": 0,
    "environment": [
      {
        "name": "CERT_NAME",
        "value": "ssl"
      },
      {
        "name": "DB_CONNECTION_STRING",
        "value": "REDACTED"
      },
      {
        "name": "VIRTUAL_HOST",
        "value": "rams.hackafe.net"
      }
    ],
    "resourceRequirements": null,
    "ulimits": null,
    "dnsServers": null,
    "mountPoints": [],
    "workingDirectory": null,
    "secrets": null,
    "dockerSecurityOptions": null,
    "memory": null,
    "memoryReservation": null,
    "volumesFrom": [],
    "stopTimeout": null,
    "image": "bitbyt3r/ubersystem:latest",
    "startTimeout": null,
    "firelensConfiguration": null,
    "dependsOn": null,
    "disableNetworking": null,
    "interactive": null,
    "healthCheck": null,
    "essential": true,
    "links": null,
    "hostname": null,
    "extraHosts": null,
    "pseudoTerminal": null,
    "user": null,
    "readonlyRootFilesystem": null,
    "dockerLabels": null,
    "systemControls": null,
    "privileged": null,
    "name": "web"
  }
]
TASK_DEFINITION

  cpu                       = 1024
  memory                    = 2048
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

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

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}


# -------------------------------------------------------------------
# MAGFest Ubersystem Containers (celery)
# -------------------------------------------------------------------

resource "aws_ecs_service" "ubersystem_celery" {
  name            = "ubersystem_celery"
  cluster         = data.aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.ubersystem_celery.arn
  desired_count   = 1
  launch_type     = "FARGATE"
}

resource "aws_ecs_task_definition" "ubersystem_celery" {
  family                    = "ubersystem_celery"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "dnsSearchDomains": null,
    "environmentFiles": null,
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "entryPoint": [],
    "portMappings": [],
    "command": [
      "celery-beat"
    ],
    "linuxParameters": null,
    "cpu": 0,
    "environment": [
      {
        "name": "DB_CONNECTION_STRING",
        "value": "REDACTED"
      }
    ],
    "resourceRequirements": null,
    "ulimits": null,
    "dnsServers": null,
    "mountPoints": [],
    "workingDirectory": null,
    "secrets": null,
    "dockerSecurityOptions": null,
    "memory": null,
    "memoryReservation": null,
    "volumesFrom": [],
    "stopTimeout": null,
    "image": "bitbyt3r/ubersystem:latest",
    "startTimeout": null,
    "firelensConfiguration": null,
    "dependsOn": null,
    "disableNetworking": null,
    "interactive": null,
    "healthCheck": null,
    "essential": true,
    "links": null,
    "hostname": null,
    "extraHosts": null,
    "pseudoTerminal": null,
    "user": null,
    "readonlyRootFilesystem": null,
    "dockerLabels": null,
    "systemControls": null,
    "privileged": null,
    "name": "celery-beat"
  },
  {
    "dnsSearchDomains": null,
    "environmentFiles": null,
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "entryPoint": [],
    "portMappings": [],
    "command": [],
    "linuxParameters": null,
    "cpu": 0,
    "environment": [
      {
        "name": "DB_CONNECTION_STRING",
        "value": "REDACTED"
      }
    ],
    "resourceRequirements": null,
    "ulimits": null,
    "dnsServers": null,
    "mountPoints": [],
    "workingDirectory": null,
    "secrets": null,
    "dockerSecurityOptions": null,
    "memory": null,
    "memoryReservation": null,
    "volumesFrom": [],
    "stopTimeout": null,
    "image": "bitbyt3r/ubersystem:latest",
    "startTimeout": null,
    "firelensConfiguration": null,
    "dependsOn": null,
    "disableNetworking": null,
    "interactive": null,
    "healthCheck": {
      "retries": 3,
      "command": [
        "celery-worker"
      ],
      "timeout": 5,
      "interval": 30,
      "startPeriod": null
    },
    "essential": true,
    "links": null,
    "hostname": null,
    "extraHosts": null,
    "pseudoTerminal": null,
    "user": null,
    "readonlyRootFilesystem": null,
    "dockerLabels": null,
    "systemControls": null,
    "privileged": null,
    "name": "celery-worker"
  }
]
TASK_DEFINITION

  cpu                       = 1024
  memory                    = 2048
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

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

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}


# -------------------------------------------------------------------
# MAGFest Ubersystem Supporting Services (RabbitMQ)
# -------------------------------------------------------------------


resource "aws_ecs_service" "rabbitmq" {
  name            = "rabbitmq"
  cluster         = data.aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1
  launch_type     = "FARGATE"
}

resource "aws_ecs_task_definition" "rabbitmq" {
  family                    = "rabbitmq"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "dnsSearchDomains": null,
    "environmentFiles": null,
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "entryPoint": [],
    "portMappings": [
      {
        "hostPort": 5672,
        "protocol": "tcp",
        "containerPort": 5672
      }
    ],
    "command": [],
    "linuxParameters": null,
    "cpu": 0,
    "environment": [
      {
        "name": "RABBITMQ_DEFAULT_PASS",
        "value": "celery"
      },
      {
        "name": "RABBITMQ_DEFAULT_USER",
        "value": "celery"
      },
      {
        "name": "RABBITMQ_DEFAULT_VHOST",
        "value": "uber"
      }
    ],
    "resourceRequirements": null,
    "ulimits": null,
    "dnsServers": null,
    "mountPoints": [],
    "workingDirectory": null,
    "secrets": null,
    "dockerSecurityOptions": null,
    "memory": null,
    "memoryReservation": null,
    "volumesFrom": [],
    "stopTimeout": null,
    "image": "rabbitmq:alpine",
    "startTimeout": null,
    "firelensConfiguration": null,
    "dependsOn": null,
    "disableNetworking": null,
    "interactive": null,
    "healthCheck": null,
    "essential": true,
    "links": null,
    "hostname": null,
    "extraHosts": null,
    "pseudoTerminal": null,
    "user": null,
    "readonlyRootFilesystem": null,
    "dockerLabels": null,
    "systemControls": null,
    "privileged": null,
    "name": "rabbitmq"
  }
]
TASK_DEFINITION

  cpu                       = 1024
  memory                    = 2048
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}


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
    Name = "ubersystem"
  }
}
