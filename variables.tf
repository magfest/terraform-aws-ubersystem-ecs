variable "ecs_cluster" {
    type    = string
}

variable "ecs_task_role" {
    type    = string
}

variable "subnet_ids" {
    type    = list(string)
}

variable "uber_web_securitygroups" {
    type    = list(string)
}

variable "rabbitmq_securitygroups" {
    type    = list(string)
}

variable "redis_securitygroups" {
    type    = list(string)
}

variable "vpc_id" {
    type    = string
}

variable "hostname" {
    type    = string
}

variable "zonename" {
    type    = string
}

variable "ubersystem_container" {
    type    = string

    default = "ghcr.io/magfest/magprime:main"
}

variable "loadbalancer_arn" {
    type    = string
}

variable "lb_web_listener_arn" {
    type    = string
}

variable "lb_priority" {
    type    = number
}

variable "prefix" {
    type    = string
    default = "uber"
}

# event, year, and environment are used to select the correct config tree in https://github.com/magfest/infrastructure/tree/master/reggie_config
variable "event" {
    type    = string
}

variable "year" {
    type    = string
}

variable "environment" {
    type    = string
}

variable "rds_instance" {
    type    = any
}

variable "db_endpoint" {
    type    = string
}

variable "db_hostname" {
    type    = string
}

variable "db_username" {
    type    = string
}

variable "db_password" {
    type    = string
}

variable "uber_db_name" {
    type    = string
}

variable "uber_db_username" {
    type    = string
}