data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3" # .name -> .region when moving to provider 6.x
  vpc_endpoint_type = "Gateway"
  # Public AND private route tables: S3 (incl. ECR image layers) stays off
  # the internet path - and off the NAT bill - from every subnet.
  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id],
  )

  tags = merge(var.tags, {
    Name = "${var.name}-s3"
  })
}
