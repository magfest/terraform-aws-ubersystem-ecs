variable "ecs_cluster" {
    type    = string
}

variable "cert_arn" {
    type    = string
}

variable "subnet_ids" {
    type    = list(string)
}

variable "security_groups" {
    type    = list(string)
}

variable "hostname" {
    type    = string
}

variable "ubersystem_container" {
    type    = string

    default = "ghcr.io/magfest/magprime:main"
}

variable "db_secret" {
    type    = string
}
