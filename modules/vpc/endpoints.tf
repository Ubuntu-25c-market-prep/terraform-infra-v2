data "aws_region" "current" {}

# Gateway endpoints (S3, DynamoDB) - the only free endpoint type: no hourly
# or per-GB charge, so both are on. Every other AWS service (and MongoDB
# Atlas via PrivateLink) is an INTERFACE endpoint, billed per AZ-hour and
# per GB, and stays out of this design.
resource "aws_vpc_endpoint" "gateway" {
  for_each = var.enable_gateway_endpoints ? toset(var.gateway_endpoints) : toset([])

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.key}" # .name -> .region when moving to provider 6.x
  vpc_endpoint_type = "Gateway"
  # Public AND private route tables: S3 (incl. ECR image layers) and
  # DynamoDB stay off the internet path - and off any NAT bill - from
  # every subnet.
  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id],
  )

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}

# The S3 endpoint predates the for_each (applied in dev): keep its state.
moved {
  from = aws_vpc_endpoint.s3[0]
  to   = aws_vpc_endpoint.gateway["s3"]
}
