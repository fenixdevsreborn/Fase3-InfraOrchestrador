# Módulo VPC — outputs

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID da VPC (fcg-fenix-main-vpc)."
}

output "vpc_cidr_block" {
  value       = aws_vpc.main.cidr_block
  description = "CIDR da VPC."
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs das subnets públicas (ordem: AZ a, b)."
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "IDs das subnets privadas (ordem: AZ a, b)."
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.main.id
  description = "ID do NAT Gateway (para referência ou dependências)."
}

output "private_route_table_id" {
  value       = aws_route_table.private.id
  description = "ID da route table privada."
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "ID da route table pública."
}
