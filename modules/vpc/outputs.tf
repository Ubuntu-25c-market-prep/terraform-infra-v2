output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Map of subnet name to subnet ID for the public subnets"
  value       = { for name, subnet in aws_subnet.public : name => subnet.id }
}

output "private_subnet_ids" {
  description = "Map of subnet name to subnet ID for the private subnets (empty when none)"
  value       = { for name, subnet in aws_subnet.private : name => subnet.id }
}

output "private_route_table_ids" {
  description = "Map of private subnet name to its route table ID"
  value       = { for name, rt in aws_route_table.private : name => rt.id }
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT gateways (empty when nat_gateway = none) - the source IPs of all private-subnet egress"
  value       = { for key, eip in aws_eip.nat : key => eip.public_ip }
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint (null when disabled)"
  value       = one(aws_vpc_endpoint.s3[*].id)
}
