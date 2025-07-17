# PocketBase Multi-Project Manager

A powerful Docker-based management system for running multiple PocketBase instances with automatic nginx reverse proxy routing.

## 🚀 Features

- **Multi-Project Support** - Run multiple PocketBase instances simultaneously
- **Dynamic Subdomain Routing** - Each project gets its own subdomain (`project.angusjs.xyz`)
- **Automatic Port Management** - Unique ports assigned automatically or manually
- **Zero-Config nginx** - Dynamic reverse proxy configuration
- **CLI Management** - Simple command-line interface for all operations
- **Health Monitoring** - Built-in health checks for all services
- **Data Persistence** - Isolated data directories for each project

## 📋 Prerequisites

- Docker & Docker Compose
- Domain configured to point to your server (`*.angusjs.xyz`)

## 🛠️ Quick Start

### 1. Clone & Setup

```bash
git clone <repository-url>
cd pb
chmod +x pbc.sh
```

### 2. Build PocketBase Image

```bash
./pbc.sh build
```

### 3. Add Your First Project

```bash
# Add project with automatic port assignment
./pbc.sh add myproject

# Or specify a custom port
./pbc.sh add myproject 8080
```

### 4. Access Your Project

Your project will be available at:
- **Subdomain**: `http://myproject.angusjs.xyz`
- **Admin Panel**: `http://myproject.angusjs.xyz/_/`

## 📖 CLI Commands

### Project Management

```bash
# Add a new project
./pbc.sh add <projectname> [port]

# Remove a project
./pbc.sh remove <projectname>

# List all projects and their status
./pbc.sh list
```

### Service Control

```bash
# Start services
./pbc.sh start <projectname|all>

# Stop services
./pbc.sh stop <projectname|all>

# Restart services
./pbc.sh restart <projectname|all>
```

### Monitoring & Maintenance

```bash
# View project logs
./pbc.sh logs <projectname>

# Show system status
./pbc.sh status

# Clean up orphaned containers
./pbc.sh cleanup

# Build/rebuild PocketBase image
./pbc.sh build
```

## 🏗️ Architecture

```
                    ┌─────────────────┐
                    │      nginx      │
                    │   (Port 80)     │
                    └─────────┬───────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
    ┌─────────▼─────────┐ ┌───▼────┐ ┌───────▼─────────┐
    │  pocketbase_app1  │ │  ...   │ │  pocketbase_app2  │
    │    (Port 8123)    │ │        │ │    (Port 8456)    │
    └───────────────────┘ └────────┘ └───────────────────┘
```

### Routing Logic

- `app1.angusjs.xyz` → `pocketbase_app1:8123`
- `app2.angusjs.xyz` → `pocketbase_app2:8456`
- `pb.angusjs.xyz` → Welcome page

## 📁 Project Structure

```
pb/
├── pbc.sh                 # Management CLI script
├── docker-compose.yml     # Docker services configuration
├── nginx.conf            # nginx reverse proxy config
├── Dockerfile            # PocketBase image definition
├── html/                 # Static web files
│   └── index.html        # Welcome page
├── pb_data_project1/     # Project 1 data (auto-created)
├── pb_data_project2/     # Project 2 data (auto-created)
└── README.md            # This file
```

## ⚙️ Configuration

### nginx Configuration

The nginx configuration automatically handles:
- Dynamic subdomain routing using regex patterns
- Port mapping via nginx map directive
- Health checks and timeouts
- Proper proxy headers

### Docker Compose

Each project gets:
- Isolated container with unique name
- Dedicated data volume
- Health check monitoring
- Automatic restart policy

### Data Persistence

Each project's data is stored in:
- `pb_data_<projectname>/` - Database, files, logs
- Automatically backed up when removing projects (optional)

## 🔧 Advanced Usage

### Custom Ports

```bash
# Add project with specific port
./pbc.sh add api-server 8080
./pbc.sh add frontend 8081
```

### Existing Projects

To migrate existing PocketBase data:

```bash
# Stop any existing PocketBase instance
# Copy your data to pb_data_projectname/
cp -r /path/to/existing/pb_data ./pb_data_myproject

# Add project
./pbc.sh add myproject 8080
```

### Multiple Environments

```bash
# Development
./pbc.sh add myapp-dev 8080

# Staging  
./pbc.sh add myapp-staging 8081

# Production
./pbc.sh add myapp-prod 8082
```

## 🚨 Troubleshooting

### Common Issues

**Project not accessible:**
```bash
# Check if containers are running
./pbc.sh status

# Check logs
./pbc.sh logs projectname

# Restart services
./pbc.sh restart all
```

**Port conflicts:**
```bash
# List current projects and ports
./pbc.sh list

# Use a different port
./pbc.sh remove conflicted-project
./pbc.sh add conflicted-project 8090
```

**nginx issues:**
```bash
# Test nginx configuration
docker run --rm -v "$(pwd)/nginx.conf:/etc/nginx/nginx.conf:ro" nginx:alpine nginx -t

# Restart nginx
./pbc.sh restart all
```

### Log Locations

- **Container logs**: `./pbc.sh logs <projectname>`
- **nginx logs**: Inside nginx container
- **PocketBase logs**: `pb_data_<project>/logs/`

## 🔒 Security Notes

- PocketBase admin panels are accessible via `/_/` path
- Consider setting up SSL/TLS certificates for production
- Data directories contain sensitive information - keep secure
- Use strong admin passwords for PocketBase instances

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📝 License

This project is open source. Please check the LICENSE file for details.

## 📞 Support

For issues and questions:
- Create an issue in the repository
- Check the troubleshooting section above
- Review Docker and nginx logs for detailed error information

---

**Happy coding with PocketBase! 🎉**
