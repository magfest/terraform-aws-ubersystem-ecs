variable "ecs_cluster" {
    type    = string
}

variable "cert_arn" {
    type    = string
}

variable "vpc_id" {
    type    = string
}

variable "subnet_ids" {
}

variable "security_groups" {
}

variable "hostname" {
    type    = string
}

variable "ubersystem_container" {
    type    = string

    default = "ghcr.io/magfest/magprime:main"
}

variable "db_location" {
    type    = string

    default = "rds"
}

variable "db_secret" {
    type    = string
}
