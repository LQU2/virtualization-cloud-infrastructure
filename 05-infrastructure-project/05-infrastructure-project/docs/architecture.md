Architecture Document

This project deploys a Content Management Stack using WordPress, MySQL, and phpMyAdmin.

WordPress provides the web interface whileMySQL is used as the backend database for storing site data. phpMyAdmin provides an interface for database management.

This stack was selected due to its simplicity and clear architecture

Component Architecture

The system follows a three tier architecture:

- Frontend: WordPress
- Backend: MySQL database
- Admin Interface: phpMyAdmin

WordPress communicates with MySQL over the backend network. phpMyAdmin also connects to MySQL for database administration.

Technology Stack

- WordPress 
- MySQL 8.0 
- phpMyAdmin 
- Docker Compose for orchestration

Network Segmentation

Two networks are used:

- Frontend network: WordPress and phpMyAdmin
- Backend network: MySQL database

The backend network is internal, so it's not accessible from outside.

Port Assignments

| Service      | Port |
|-------------|------|
| WordPress   | 8080 |
| phpMyAdmin  | 8081 |
| MySQL       | 3306 |


Traffic Flow

- Users access WordPress via port 8080
- WordPress communicates with MySQL 
- phpMyAdmin connects to MySQL via backend network

Security Boundaries

- Only WordPress and phpMyAdmin are exposed externally
- MySQL is isolated in an internal network

Persistent Data

- MySQL database files
- WordPress content and uploads

Volume Strategy

Docker volumes are used:

- db_data -> MySQL data
- wp_data -> WordPress content


Backup Strategy

Database backups can be created using mysqldump and stored externally. Recovery involves restoring the dump file into MySQL.

Security Considerations

- Credentials are stored in environment variables
- Database is not exposed externally
- Containers are isolated using Docker networks

Horizontal Scaling

WordPress containers can be scaled using multiple replicas

Vertical Scaling

Resources (CPU and RAM) can be increased for MySQL and WordPress containers.

Production Roadmap

Future improvements include

- Implementing secrets management
- Migrating to Kubernetes
