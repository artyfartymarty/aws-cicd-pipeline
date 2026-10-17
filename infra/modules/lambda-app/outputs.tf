output "function_name" {
  value = aws_lambda_function.app.function_name
}

output "table_name" {
  value = aws_dynamodb_table.items.name
}

output "s3_key" {
  value = aws_lambda_function.app.s3_key
}

output "role_name" {
  value = aws_iam_role.app.name
}

output "permissions_boundary" {
  value = aws_iam_role.app.permissions_boundary
}

output "deletion_protection" {
  value = aws_dynamodb_table.items.deletion_protection_enabled
}

output "in_vpc" {
  value = length(var.subnet_ids) > 0
}
