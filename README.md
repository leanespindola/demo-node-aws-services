Aplicación Node.js desplegada en AWS usando ECS Fargate con almacenamiento en DynamoDB. Incluye infraestructura como código con Terraform para:
* Repositorio ECR con política de lifecycle.
* Tabla DynamoDB Items.
* Cluster ECS y definición de task.
* Servicio ECS con Fargate.
* Application Load Balancer con Target Group y health check.
Permite probar endpoints HTTP (POST /item, GET /item/{id}) a través del ALB o directamente por la IP del contenedor.
