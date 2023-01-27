terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.38.0"
    }
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
  }
}

# -------------------------------------------------------------------
# Import Data block for AWS information
# -------------------------------------------------------------------

data "aws_vpc" "uber" {
  id = var.vpc_id
}

# -------------------------------------------------------------------
# MAGFest Ubersystem Load Balancer
# -------------------------------------------------------------------

resource "aws_acm_certificate" "uber" {
  domain_name       = var.hostname
  validation_method = "DNS"
}

data "aws_route53_zone" "uber" {
  name         = var.zonename
  private_zone = false
}

resource "aws_route53_record" "uber" {
  for_each = {
    for dvo in aws_acm_certificate.uber.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.uber.zone_id
}

resource "aws_acm_certificate_validation" "uber" {
  certificate_arn         = aws_acm_certificate.uber.arn
  validation_record_fqdns = [for record in aws_route53_record.uber : record.fqdn]
}

resource "aws_route53_record" "public" {
  zone_id = var.zonename
  name    = var.hostname
  type    = "CNAME"
  ttl     = 5
  records = [
    var.loadbalancer_dns_name
  ]
}

resource "aws_lb_target_group" "ubersystem_web" {
  name_prefix   = "${var.prefix}"
  port          = 80
  protocol      = "HTTP"
  target_type   = "ip"
  vpc_id        = data.aws_vpc.uber.id

  health_check {
    healthy_threshold   = 2
    interval            = 30
    unhealthy_threshold = 10
    timeout             = 5
    path                = "/"
    matcher             = "200-499"
  }
}

resource "aws_lb_listener_certificate" "uber" {
  listener_arn    = var.lb_web_listener_arn
  certificate_arn = aws_acm_certificate_validation.uber.certificate_arn
}

resource "aws_lb_listener_rule" "uber" {
  listener_arn = var.lb_web_listener_arn
  priority     = var.lb_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ubersystem_web.arn
  }

  condition {
    host_header {
      values = [var.hostname]
    }
  }
}

# -------------------------------------------------------------------
# MAGFest Ubersystem Containers (web)
# -------------------------------------------------------------------

resource "aws_efs_access_point" "uber" {
  file_system_id = var.efs_id

  root_directory {
    path = var.efs_dir
    creation_info {
      owner_gid   = 65534
      owner_uid   = 65534
      permissions = 0755
    }
  }
}

resource "aws_ecs_service" "ubersystem_web" {
  name            = "ubersystem_web"
  cluster         = var.ecs_cluster
  task_definition = aws_ecs_task_definition.ubersystem_web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.uber_web_securitygroups
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
        "value": "redis"
      },
      {
        "name": "BROKER_HOST",
        "value": "rabbitmq"
      },
      {
        "name": "CONFIG_EVENT",
        "value": "${var.event}"
      },
      {
        "name": "CONFIG_YEAR",
        "value": "${var.year}"
      },
      {
        "name": "CONFIG_ENVIRONMENT",
        "value": "${var.environment}"
      },
      {
        "name": "CONFIG_HOSTNAME",
        "value": "${var.hostname}"
      },
      {
        "name": "DB_CONNECTION_STRING",
        "value": "postgresql://${var.uber_db_username}:${aws_secretsmanager_secret_version.password.secret_string}@${var.db_endpoint}/${var.uber_db_name}"
      }
    ],
    "image": "${var.ubersystem_container}",
    "essential": true,
    "name": "web",
    "mountPoints": [
      {
        "sourceVolume": "static",
        "containerPath": "/srv/mnt/reggie/uploaded_files",
        "readOnly": true
      }
    ]
  }
]
TASK_DEFINITION

  volume {
    name = "static"

    efs_volume_configuration {
      file_system_id          = var.efs_id
      root_directory          = var.efs_dir
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2999
      authorization_config {
        access_point_id = aws_efs_access_point.uber.id
        iam             = "ENABLED"
      }
    }
  }

  cpu                       = 1024
  memory                    = 2048
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = var.ecs_task_role

  task_role_arn = var.ecs_task_role

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
  cluster         = var.ecs_cluster
  task_definition = aws_ecs_task_definition.ubersystem_celery.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets           = var.subnet_ids
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
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "command": [
      "celery-beat"
    ],
    "environment": [
      {
        "name": "DB_CONNECTION_STRING",
        "value": "postgresql://${var.uber_db_username}:${aws_secretsmanager_secret_version.password.secret_string}@${var.db_endpoint}/${var.uber_db_name}"
      }
    ],
    "image": "${var.ubersystem_container}",
    "essential": true,
    "name": "celery-beat",
    "mountPoints": [
      {
        "sourceVolume": "static",
        "containerPath": "/srv/mnt/reggie/uploaded_files",
        "readOnly": true
      }
    ]
  },
  {
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/Ubersystem",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "environment": [
      {
        "name": "DB_CONNECTION_STRING",
        "value": "postgresql://${var.uber_db_username}:${aws_secretsmanager_secret_version.password.secret_string}@${var.db_endpoint}/${var.uber_db_name}"
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
    "name": "celery-worker",
    "mountPoints": [
      {
        "sourceVolume": "static",
        "containerPath": "/srv/mnt/reggie/uploaded_files",
        "readOnly": true
      }
    ]
  }
]
TASK_DEFINITION

  volume {
    name = "static"

    efs_volume_configuration {
      file_system_id          = var.efs_id
      root_directory          = var.efs_dir
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2999
      authorization_config {
        access_point_id = aws_efs_access_point.uber.id
        iam             = "ENABLED"
      }
    }
  }

  cpu                       = 256
  memory                    = 512
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = var.ecs_task_role

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
  cluster         = var.ecs_cluster
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.rabbitmq_securitygroups
    assign_public_ip  = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.rabbitmq.arn
  }
}

resource "aws_ecs_task_definition" "rabbitmq" {
  family                    = "rabbitmq"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "logConfiguration": {
      "logDriver": "awslogs",
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
    "name": "rabbitmq"
  }
]
TASK_DEFINITION

  cpu                       = 256
  memory                    = 512
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  task_role_arn = var.ecs_task_role
}

# -------------------------------------------------------------------
# MAGFest Ubersystem Supporting Services (Redis)
# -------------------------------------------------------------------

resource "aws_ecs_service" "redis" {
  name            = "redis"
  cluster         = var.ecs_cluster
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.redis_securitygroups
    assign_public_ip  = true
  }
  
  service_registries {
    registry_arn = aws_service_discovery_service.redis.arn
  }
}

resource "aws_ecs_task_definition" "redis" {
  family                    = "redis"
  container_definitions     = <<TASK_DEFINITION
[
  {
    "logConfiguration": {
      "logDriver": "awslogs",
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
    "name": "redis"
  }
]
TASK_DEFINITION

  cpu                       = 256
  memory                    = 512
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  execution_role_arn        = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  task_role_arn = "${var.ecs_task_role}"
}

# -------------------------------------------------------------------
# DNS Service Discovery
# -------------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "uber" {
  name        = var.hostname
  description = "Uber Internal Services (${var.hostname})"
  vpc         = data.aws_vpc.uber.id
}

resource "aws_service_discovery_service" "redis" {
  name = "redis"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.uber.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "rabbitmq" {
  name = "rabbitmq"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.uber.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# -------------------------------------------------------------------
# Database
# -------------------------------------------------------------------

provider "postgresql" {
  alias      = "uber"
  host       = var.db_hostname
  username   = var.db_username
  password   = var.db_password
  superuser  = false
}

resource "random_password" "uber" {
  length            = 40
  special           = false
  keepers           = {
    pass_version  = 2
  }
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.prefix}-db-password"
}

resource "aws_secretsmanager_secret_version" "password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.uber.result
}

resource "postgresql_database" "uber" {
  provider          = postgresql.uber
  name              = var.uber_db_name
  owner             = var.uber_db_username
  template          = "template0"
  lc_collate        = "C"
  connection_limit  = -1
  allow_connections = true
  depends_on = [
    postgresql_role.uber,
    var.rds_instance
  ]
}

resource "postgresql_role" "uber" {
  provider         = postgresql.uber
  name             = var.uber_db_username
  login            = true
  connection_limit = -1
  password         = aws_secretsmanager_secret_version.password.secret_string
  depends_on = [
    var.rds_instance
  ]
}