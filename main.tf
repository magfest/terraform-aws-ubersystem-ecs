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

resource "aws_lb" "ubersystem" {
  name_prefix        = "uber"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_groups
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  # access_logs {
  #   bucket  = aws_s3_bucket.lb_logs.bucket
  #   prefix  = "test-lb"
  #   enabled = true
  # }

  # tags = {
  #   Environment = "production"
  # }
}

resource "aws_lb_target_group" "ubersystem_web" {
  name_prefix   = "uber"
  port          = 80
  protocol      = "HTTP"
  target_type   = "ip"
  vpc_id        = var.vpc_id
}

resource "aws_lb_listener" "ubersystem_web" {
  load_balancer_arn = aws_lb.ubersystem.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ubersystem_web.arn
  }
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

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.security_groups
    assign_public_ip  = true
  }

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
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "portMappings": [
      {
        "hostPort": 8282,
        "protocol": "tcp",
        "containerPort": 8282
      }
    ],
    "environment": [
      {
        "name": "CERT_NAME",
        "value": "ssl"
      },
      {
        "name": "VIRTUAL_HOST",
        "value": "${var.hostname}"
      },
      {
        "name": "SESSION_HOST",
        "value": "${aws_appmesh_virtual_service.redis.name}"
      },
      {
        "name": "BROKER_HOST",
        "value": "${aws_appmesh_virtual_service.rabbitmq.name}"
      }
    ],
    "secrets": [
      {
        "name": "DB_CONNECTION_STRING",
        "valueFrom": "${var.db_secret}"
      }
    ],
    "image": "${var.ubersystem_container}",
    "essential": true,
    "name": "web",
    "dependsOn": [ 
      { 
        "containerName": "envoy",
        "condition": "HEALTHY" 
      }
    ]
  },
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "environment": [
      {
        "name": "APPMESH_VIRTUAL_NODE_NAME",
        "value": "${aws_appmesh_virtual_node.web.arn}"
      }
    ],
    "image": "public.ecr.aws/appmesh/aws-appmesh-envoy:v1.23.1.0-prod",
    "healthCheck": {
      "retries": 3,
      "command": [
        "CMD-SHELL",
        "curl -s http://localhost:9901/server_info | grep state | grep -q LIVE"
      ],
      "timeout": 2,
      "interval": 5,
      "startPeriod": 10
    },
    "essential": true,
    "user": "1337",
    "name": "envoy"
  }
]
TASK_DEFINITION

  cpu                       = 1024
  memory                    = 2048
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

  depends_on = [
    aws_lb_listener.ubersystem_web
  ]

  task_role_arn = aws_iam_role.task_role.arn
  proxy_configuration {
    type           = "APPMESH"
    container_name = "envoy"
    properties = {
      AppPorts         = "8282"
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
      IgnoredUID       = "1337"
      ProxyEgressPort  = 15001
      ProxyIngressPort = 15000
    }
  }

  # volume {
  #   name = "static-files"

  #   efs_volume_configuration {
  #     file_system_id          = aws_efs_file_system.ubersystem_static.id
  #     root_directory          = "/"
  #     # transit_encryption      = "ENABLED"
  #     # transit_encryption_port = 2999
  #     # authorization_config {
  #     #   access_point_id = aws_efs_access_point.test.id
  #     #   iam             = "ENABLED"
  #     # }
  #   }
  # }

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

resource "aws_appmesh_virtual_service" "web" {
  name      = "web.${aws_appmesh_mesh.ubersystem.name}.local"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    provider {
      virtual_node {
        virtual_node_name = aws_appmesh_virtual_node.web.name
      }
    }
  }
}

resource "aws_appmesh_virtual_node" "web" {
  name      = "web"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    backend {
      virtual_service {
        virtual_service_name = aws_appmesh_virtual_service.rabbitmq.name
      }
    }

    backend {
      virtual_service {
        virtual_service_name = aws_appmesh_virtual_service.redis.name
      }
    }

    listener {
      port_mapping {
        port     = 8282
        protocol = "tcp"
      }
    }

    service_discovery {
      dns {
        hostname = "web"
      }
    }
  }
}

resource "aws_appmesh_virtual_router" "web" {
  name      = "web"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    listener {
      port_mapping {
        port     = 8282
        protocol = "tcp"
      }
    }
  }
}

resource "aws_appmesh_route" "web" {
  name                = "web"
  mesh_name           = aws_appmesh_mesh.ubersystem.id
  virtual_router_name = aws_appmesh_virtual_router.web.name

  spec {
    tcp_route {
      action {
        weighted_target {
          virtual_node = aws_appmesh_virtual_node.web.name
          weight       = 100
        }
      }
    }
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

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.security_groups
    assign_public_ip  = true
  }
}

resource "aws_ecs_task_definition" "ubersystem_celery" {
  family                    = "ubersystem_celery"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "command": [
      "celery-beat"
    ],
    "secrets": [
      {
        "name": "DB_CONNECTION_STRING",
        "valueFrom": "${var.db_secret}"
      }
    ],
    "image": "${var.ubersystem_container}",
    "essential": true,
    "name": "celery-beat"
  },
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "secrets": [
      {
        "name": "DB_CONNECTION_STRING",
        "valueFrom": "${var.db_secret}"
      }
    ],
    "image": "${var.ubersystem_container}",
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
    "name": "celery-worker"
  }
]
TASK_DEFINITION

  cpu                       = 256
  memory                    = 512
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

  # volume {
  #   name = "static-files"

  #   efs_volume_configuration {
  #     file_system_id          = aws_efs_file_system.ubersystem_static.id
  #     root_directory          = "/"
  #     # transit_encryption      = "ENABLED"
  #     # transit_encryption_port = 2999
  #     # authorization_config {
  #     #   access_point_id = aws_efs_access_point.test.id
  #     #   iam             = "ENABLED"
  #     # }
  #   }
  # }

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

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.security_groups
    assign_public_ip  = true
  }
}

resource "aws_ecs_task_definition" "rabbitmq" {
  family                    = "rabbitmq"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "portMappings": [
      {
        "hostPort": 5672,
        "protocol": "tcp",
        "containerPort": 5672
      }
    ],
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
    "image": "public.ecr.aws/docker/library/rabbitmq:alpine",
    "essential": true,
    "name": "rabbitmq",
    "dependsOn": [ 
      { 
        "containerName": "envoy",
        "condition": "HEALTHY" 
      }
    ] 
  },
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "environment": [
      {
        "name": "APPMESH_VIRTUAL_NODE_NAME",
        "value": "${aws_appmesh_virtual_node.rabbitmq.arn}"
      }
    ],
    "image": "public.ecr.aws/appmesh/aws-appmesh-envoy:v1.23.1.0-prod",
    "healthCheck": {
      "retries": 3,
      "command": [
        "CMD-SHELL",
        "curl -s http://localhost:9901/server_info | grep state | grep -q LIVE"
      ],
      "timeout": 2,
      "interval": 5,
      "startPeriod": 10
    },
    "essential": true,
    "user": "1337",
    "name": "envoy"
  }
]
TASK_DEFINITION

  cpu                       = 256
  memory                    = 512
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  task_role_arn = aws_iam_role.task_role.arn
  proxy_configuration {
    type           = "APPMESH"
    container_name = "envoy"
    properties = {
      AppPorts         = "5672"
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
      IgnoredUID       = "1337"
      ProxyEgressPort  = 15001
      ProxyIngressPort = 15000
    }
  }
}

resource "aws_appmesh_virtual_service" "rabbitmq" {
  name      = "rabbitmq.${aws_appmesh_mesh.ubersystem.name}.local"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    provider {
      virtual_node {
        virtual_node_name = aws_appmesh_virtual_node.rabbitmq.name
      }
    }
  }
}

resource "aws_appmesh_virtual_node" "rabbitmq" {
  name      = "rabbitmq"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    listener {
      port_mapping {
        port     = 5672
        protocol = "tcp"
      }
    }

    service_discovery {
      dns {
        hostname = aws_appmesh_virtual_service.rabbitmq.name
      }
    }
  }
}

resource "aws_appmesh_virtual_router" "rabbitmq" {
  name      = "rabbitmq"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    listener {
      port_mapping {
        port     = 5672
        protocol = "tcp"
      }
    }
  }
}

resource "aws_appmesh_route" "rabbitmq" {
  name                = "rabbitmq"
  mesh_name           = aws_appmesh_mesh.ubersystem.id
  virtual_router_name = aws_appmesh_virtual_router.rabbitmq.name

  spec {
    tcp_route {
      action {
        weighted_target {
          virtual_node = aws_appmesh_virtual_node.rabbitmq.name
          weight       = 100
        }
      }
    }
  }
}


# -------------------------------------------------------------------
# MAGFest Ubersystem Supporting Services (Redis)
# -------------------------------------------------------------------

resource "aws_ecs_service" "redis" {
  name            = "redis"
  cluster         = data.aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.security_groups
    assign_public_ip  = true
  }
}

resource "aws_ecs_task_definition" "redis" {
  family                    = "redis"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "portMappings": [
      {
        "hostPort": 6379,
        "protocol": "tcp",
        "containerPort": 6379
      }
    ],
    "environment": [
      {
        "name": "ALLOW_EMPTY_PASSWORD",
        "value": "true"
      }
    ],
    "image": "public.ecr.aws/ubuntu/redis:latest",
    "essential": true,
    "name": "redis",
    "dependsOn": [ 
      { 
        "containerName": "envoy",
        "condition": "HEALTHY" 
      }
    ]
  },
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "secretOptions": null,
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "environment": [
      {
        "name": "APPMESH_VIRTUAL_NODE_NAME",
        "value": "${aws_appmesh_virtual_node.redis.arn}"
      }
    ],
    "image": "public.ecr.aws/appmesh/aws-appmesh-envoy:v1.23.1.0-prod",
    "healthCheck": {
      "retries": 3,
      "command": [
        "CMD-SHELL",
        "curl -s http://localhost:9901/server_info | grep state | grep -q LIVE"
      ],
      "timeout": 2,
      "interval": 5,
      "startPeriod": 10
    },
    "essential": true,
    "user": "1337",
    "name": "envoy"
  }
]
TASK_DEFINITION

  cpu                       = 256
  memory                    = 512
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  task_role_arn = aws_iam_role.task_role.arn
  proxy_configuration {
    type           = "APPMESH"
    container_name = "envoy"
    properties = {
      AppPorts         = "6379"
      EgressIgnoredIPs = "169.254.170.2,169.254.169.254"
      IgnoredUID       = "1337"
      ProxyEgressPort  = 15001
      ProxyIngressPort = 15000
    }
  }
}

resource "aws_appmesh_virtual_service" "redis" {
  name      = "redis.${aws_appmesh_mesh.ubersystem.name}.local"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    provider {
      virtual_node {
        virtual_node_name = aws_appmesh_virtual_node.redis.name
      }
    }
  }
}

resource "aws_appmesh_virtual_node" "redis" {
  name      = "redis"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    listener {
      port_mapping {
        port     = 6379
        protocol = "tcp"
      }
    }

    service_discovery {
      dns {
        hostname = aws_appmesh_virtual_service.redis.name
      }
    }
  }
}

resource "aws_appmesh_virtual_router" "redis" {
  name      = "redis"
  mesh_name = aws_appmesh_mesh.ubersystem.id

  spec {
    listener {
      port_mapping {
        port     = 6379
        protocol = "tcp"
      }
    }
  }
}

resource "aws_appmesh_route" "redis" {
  name                = "redis"
  mesh_name           = aws_appmesh_mesh.ubersystem.id
  virtual_router_name = aws_appmesh_virtual_router.redis.name

  spec {
    tcp_route {
      action {
        weighted_target {
          virtual_node = aws_appmesh_virtual_node.redis.name
          weight       = 100
        }
      }
    }
  }
}

# -------------------------------------------------------------------
# MAGFest Ubersystem Shared File Directory
# -------------------------------------------------------------------

resource "aws_efs_file_system" "ubersystem_static" {
  creation_token = "ubersystem"

  tags = {
    Name = "ubersystem"
  }
}

# -------------------------------------------------------------------
# MAGFest Envoy Service Mesh (AWS App Mesh)
# -------------------------------------------------------------------

resource "aws_appmesh_mesh" "ubersystem" {
  name = "ubersystem"

  spec {
    egress_filter {
      type = "ALLOW_ALL"
    }
  }
}

resource "aws_iam_role" "task_role" {
  name_prefix = "uber"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_role_envoy" {
  role       = aws_iam_role.task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess"
}

