variable "vkcs_username" {
  description = "VK Cloud username"
  type        = string
  sensitive   = true
}

variable "vkcs_password" {
  description = "VK Cloud password"
  type        = string
  sensitive   = true
}

variable "vkcs_project_id" {
  description = "VK Cloud project ID"
  type        = string
  sensitive   = true
}

variable "vkcs_region" {
  description = "VK Cloud region"
  type        = string
  default     = "RegionOne"
}

variable "existing_network_id" {
  description = "Existing network ID"
  type        = string
  default     = "78368ec6-9b7d-4a88-b833-9ad0df8010f4"
}


variable "db_password" {
  description = "Password for database user"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}
