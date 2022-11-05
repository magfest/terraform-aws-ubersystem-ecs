variable "ecs_cluster" {
    type    = string
}

variable "lb_arn" {
    type    = string
    
    default = "null"
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

variable "db_location" {
    type    = string

    default = "container"
}

variable "db_secret" {
    type    = string

    default = "null"
}
