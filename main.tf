variable "profile_aws" {}

variable "files_to_upload" {
    default = [ "index.html", "favicon.ico", "main-LYA2L3LL.js", "polyfills-SCHOHYNV.js" , "styles-5INURTSO.css"]
}

variable "files_mime" {
    default = [ "text/html", "image/vnd.microsoft.icon", "text/javascript", "text/javascript" , "text/css"]
}

variable "region" {
    default = "us-east-2"
}

provider "aws" {
  profile = var.profile_aws
  region  = var.region
}

##---------------------------------VPC--------------------------------------

resource "aws_vpc" "vpc_bigstoremanager" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "vpc-bigstoremanager"
  }
}

resource "aws_internet_gateway" "igw_bigstoremanager" {
  vpc_id = aws_vpc.vpc_bigstoremanager.id

  tags = {
    Name = "igw-bigstoremanager"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc_bigstoremanager.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc_bigstoremanager.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_bigstoremanager.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

##---------------------------------APIGW--------------------------------------

resource "aws_apigatewayv2_api" "api_bigstoremanager" {
  name          = "apigw-bigstoremanager"
  protocol_type = "HTTP"
}

resource "aws_lambda_function" "lambda_bigstoremanager_api" {
  function_name = "lambda-bigstoremanager-api"
  handler       = "app.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      FLASK_ENV = "production"
    }
  }
  filename         = "./artifacts/lambda-python.zip"
  source_code_hash = filebase64sha256("./artifacts/lambda-python.zip")

  tags = {
    Name = "lambda-bigstoremanager-api"
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.api_bigstoremanager.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.lambda_bigstoremanager_api.arn
}

resource "aws_apigatewayv2_route" "proxy_route" {
  api_id    = aws_apigatewayv2_api.api_bigstoremanager.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_bigstoremanager_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:apigateway:${var.region}::/restapis/${aws_apigatewayv2_api.api_bigstoremanager.id}/*/*"
}

##------------------------------------S3_STATIC-----------------------------------------

resource "aws_s3_bucket" "angular_s3" {
  bucket = "bigstoremanager-fs"

  website {
    index_document = "index.html"
    error_document = "index.html"
  }

  tags = {
    Name = "bigstoremanager-fs"
  }
}

resource "aws_s3_bucket_object" "angular_app" {

    count = length(var.files_to_upload)

  bucket = aws_s3_bucket.angular_s3.bucket
  key    = "${element(var.files_to_upload, count.index)}"
  source = "./artifacts/${element(var.files_to_upload, count.index)}"
  etag         = filemd5("./artifacts/${element(var.files_to_upload, count.index)}")
  content_type = "${element(var.files_mime, count.index)}"
}


##---------------------------------------DBS----------------------------------------

resource "aws_db_instance" "sqldb_bigstoremanager" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0.35"
  instance_class         = "db.t3.micro"
  db_name                = "bigstoremanager"
  username               = "admin_master_username"
  password               = "admin_master_username"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true

  tags = {
    Name = "sqldb-bigstoremanager"
  }
}

resource "aws_docdb_cluster" "docsdb_bigstoremanager" {
  cluster_identifier     = "docsdb-bigstoremanager"
  engine                 = "docdb"
  master_username        = "admin_master_username"
  master_password        = "admin_master_password"

  tags = {
    Name = "docsdb-bigstoremanager"
  }
}


##-------------------------------IAM--------------------------------

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-bigstoremanager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "lambda-exec-role-bigstoremanager"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_rds_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_docdb_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDocDBFullAccess"
}

#----------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "angular_s3_public_access_block" {
  bucket = aws_s3_bucket.angular_s3.id

  block_public_acls          = false
  ignore_public_acls         = false
  block_public_policy        = false
  restrict_public_buckets    = false
}
resource "aws_s3_bucket_policy" "angular_s3_policy" {
  bucket = aws_s3_bucket.angular_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "s3:GetObject"
        Effect    = "Allow"
        Resource  = "${aws_s3_bucket.angular_s3.arn}/*"
        Principal = "*"
      }
    ]
  })
}