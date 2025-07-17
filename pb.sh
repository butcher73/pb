#!/usr/bin/env bash
set -euo pipefail

# Configuration
COMPOSE="docker-compose.yml"
NGINX="nginx.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

usage() {
  cat <<EOF
${BLUE}PocketBase Container Manager${NC}

Usage:
  $0 add <projectname> [port]     - Add a new PocketBase project
  $0 remove <projectname>         - Remove a PocketBase project
  $0 list                         - List all projects and their status
  $0 start <projectname|all>      - Start project(s)
  $0 stop <projectname|all>       - Stop project(s)
  $0 restart <projectname|all>    - Restart project(s)
  $0 logs <projectname>           - Show logs for a project
  $0 cleanup                      - Clean up orphaned containers
  $0 status                       - Show overall system status
  $0 build                        - Build the PocketBase image

Examples:
  $0 add myproject 8080          # Add project with specific port
  $0 add myproject               # Add project with random port
  $0 start all                   # Start all services
  $0 logs myproject              # View project logs

EOF
  exit 1
}

# Validation functions
validate_project_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Invalid project name. Use only letters, numbers, hyphens, and underscores."
    exit 1
  fi
}

validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
    log_error "Invalid port number. Use a number between 1024 and 65535."
    exit 1
  fi
}

check_dependencies() {
  command -v docker >/dev/null 2>&1 || { log_error "Docker is required but not installed."; exit 1; }
  
  # Check for docker compose (new) or docker-compose (old)
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
  else
    log_error "Docker Compose is required but not installed. Please install Docker Compose."
    exit 1
  fi
  
  log_info "Using Docker Compose command: $DOCKER_COMPOSE"
}

# Core functions
add_nginx_route() {
  local PROJECT="$1"
  local PORT="$2"
  
  # Add project to nginx map
  if grep -q "map \$project \$upstream_port" "$NGINX"; then
    # Add to existing map
    sed -i "/map \$project \$upstream_port {/a\\    ${PROJECT}    ${PORT};" "$NGINX"
  else
    # Create new map section
    sed -i "/resolver 127.0.0.11/a\\    \\n    map \$project \$upstream_port {\\n        default    8090;\\n        ${PROJECT}    ${PORT};\\n    }" "$NGINX"
  fi
  log_success "Added nginx route for $PROJECT:$PORT"
}

remove_nginx_route() {
  local PROJECT="$1"
  
  # Remove project from nginx map
  sed -i "/^\s*${PROJECT}\s\+[0-9]\+;$/d" "$NGINX"
  log_success "Removed nginx route for $PROJECT"
}

list_projects() {
  log_info "Listing PocketBase projects..."
  
  if [ ! -f "$COMPOSE" ]; then
    log_error "Docker Compose file not found: $COMPOSE"
    return 1
  fi

  local projects=()
  while IFS= read -r line; do
    projects+=("$line")
  done < <(grep -oP 'pocketbase_\K[\w-]+' "$COMPOSE" 2>/dev/null | sort || true)

  if [ ${#projects[@]} -eq 0 ]; then
    log_warning "No projects found."
    return 0
  fi

  local statuses
  statuses=$($DOCKER_COMPOSE ps --format "{{.Name}} {{.State}}" 2>/dev/null | grep pocketbase_ || true)
  
  printf "\n${BLUE}%-20s%-15s%-10s${NC}\n" "Project" "Status" "Port"
  printf "%-45s\n" "---------------------------------------------"
  
  for project in "${projects[@]}"; do
    local name="pocketbase_$project"
    local status="not created"
    local port=""
    
    if [ -n "$statuses" ]; then
      status=$(echo "$statuses" | awk -v n="$name" '$1==n {print $2}' || echo "not created")
    fi
    
    # Extract port from compose file
    port=$(awk -v proj="$project" '
      /pocketbase_'"$project"':/{flag=1; next}
      flag && /command:/{
        if(match($0, /:([0-9]+)/)) {
          print substr($0, RSTART+1, RLENGTH-1)
        }
        flag=0
      }
      flag && /^[[:space:]]*[a-zA-Z]/ && !/command:/{flag=0}
    ' "$COMPOSE" 2>/dev/null || echo "unknown")
    
    # Color code status
    case "$status" in
      "running") status="${GREEN}running${NC}" ;;
      "exited") status="${RED}exited${NC}" ;;
      "not created") status="${YELLOW}not created${NC}" ;;
    esac
    
    printf "%-20s%-25s%-10s\n" "$project" "$status" "$port"
  done
  echo
}

add_project() {
  local PROJECT="$1"
  local PORT="${2:-$(shuf -i 8100-8999 -n 1)}"  # Generate random port if not specified
  local DATA_DIR="pb_data_${PROJECT}"

  validate_project_name "$PROJECT"
  validate_port "$PORT"

  # Check if project already exists
  if grep -q "pocketbase_${PROJECT}:" "$COMPOSE"; then
    log_error "Project '$PROJECT' already exists."
    exit 1
  fi

  # Check if port is already in use
  if grep -q ":${PORT}" "$COMPOSE"; then
    log_error "Port $PORT is already in use by another project."
    exit 1
  fi

  log_info "Adding project '$PROJECT' on port $PORT..."

  # Create data directory
  mkdir -p "$DATA_DIR"
  log_success "Created data directory: $DATA_DIR"

  # Add service to docker-compose.yml
  cat >> "$COMPOSE" <<EOF

  pocketbase_${PROJECT}:
    image: local/pocketbase:latest
    container_name: pocketbase_${PROJECT}
    restart: always
    command: serve --http=0.0.0.0:${PORT}
    volumes:
      - ./${DATA_DIR}:/pb_data
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${PORT}/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

  log_success "Added service pocketbase_$PROJECT (port $PORT)"

  # Update nginx depends_on
  if grep -q "^\s*depends_on:" "$COMPOSE"; then
    if ! grep -q "pocketbase_${PROJECT}" <<< "$(grep -A10 'depends_on:' "$COMPOSE")"; then
      sed -i "/^\s*depends_on:/a\      - pocketbase_${PROJECT}" "$COMPOSE"
      log_success "Updated nginx dependencies"
    fi
  else
    sed -i "/image: nginx:alpine/a\    depends_on:\n      - pocketbase_${PROJECT}" "$COMPOSE"
    log_success "Added nginx dependencies"
  fi

  # Update nginx config with the project's specific port
  add_nginx_route "$PROJECT" "$PORT"

  # Start the services
  log_info "Starting services..."
  if $DOCKER_COMPOSE up -d "pocketbase_${PROJECT}" nginx --remove-orphans; then
    log_success "Project '$PROJECT' started successfully!"
    log_info "Access your project at:"
    log_info "  - http://${PROJECT}.angusjs.xyz"
  else
    log_error "Failed to start project '$PROJECT'"
    exit 1
  fi
}

remove_project() {
  local PROJECT="$1"
  local DATA_DIR="pb_data_${PROJECT}"

  validate_project_name "$PROJECT"

  if ! grep -q "pocketbase_${PROJECT}:" "$COMPOSE"; then
    log_error "Project '$PROJECT' not found."
    exit 1
  fi

  log_info "Removing project '$PROJECT'..."

  # Stop and remove container
  log_info "Stopping and removing container..."
  $DOCKER_COMPOSE stop "pocketbase_${PROJECT}" 2>/dev/null || true
  $DOCKER_COMPOSE rm -f "pocketbase_${PROJECT}" 2>/dev/null || true

  # Remove from docker-compose.yml
  awk -v svc="pocketbase_${PROJECT}:" '
    BEGIN{del=0; blank_lines=0}
    {
      if($1==svc) {
        del=1
        blank_lines=0
        next
      }
      if(del && /^[^ \t]/ && !/^$/) {
        del=0
        blank_lines=0
      }
      if(del && /^$/) {
        blank_lines++
        if(blank_lines <= 1) next
      }
      if(!del) print
    }
  ' "$COMPOSE" > "${COMPOSE}.tmp" && mv "${COMPOSE}.tmp" "$COMPOSE"

  log_success "Removed service from docker-compose.yml"

  # Remove nginx dependencies
  sed -i "/^\s*- pocketbase_${PROJECT}$/d" "$COMPOSE"

  # Remove nginx route
  remove_nginx_route "$PROJECT"

  # Remove data directory with confirmation
  if [ -d "$DATA_DIR" ]; then
    read -p "Remove data directory '$DATA_DIR'? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf "$DATA_DIR"
      log_success "Removed data directory: $DATA_DIR"
    else
      log_warning "Data directory preserved: $DATA_DIR"
    fi
  fi

  # Restart nginx to apply changes
  log_info "Restarting nginx..."
  $DOCKER_COMPOSE up -d nginx --remove-orphans

  log_success "Project '$PROJECT' removed successfully!"
}

show_logs() {
  local PROJECT="$1"
  validate_project_name "$PROJECT"

  if ! grep -q "pocketbase_${PROJECT}:" "$COMPOSE"; then
    log_error "Project '$PROJECT' not found."
    exit 1
  fi

  log_info "Showing logs for project '$PROJECT'..."
  $DOCKER_COMPOSE logs -f "pocketbase_${PROJECT}"
}

show_status() {
  log_info "System Status"
  echo "----------------------------------------"
  
  # Check if Docker is running
  if docker info >/dev/null 2>&1; then
    log_success "Docker is running"
  else
    log_error "Docker is not running"
    return 1
  fi

  # Check nginx status
  if $DOCKER_COMPOSE ps nginx --format "{{.State}}" 2>/dev/null | grep -q "running"; then
    log_success "Nginx is running"
  else
    log_warning "Nginx is not running"
  fi

  # Show resource usage
  echo
  log_info "Container Resource Usage:"
  docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $($DOCKER_COMPOSE ps -q 2>/dev/null) 2>/dev/null || log_warning "No containers running"
  
  echo
  list_projects
}

build_image() {
  log_info "Building PocketBase Docker image..."
  if docker build -t local/pocketbase:latest .; then
    log_success "PocketBase image built successfully!"
  else
    log_error "Failed to build PocketBase image"
    exit 1
  fi
}

cleanup() {
  log_info "Cleaning up orphaned containers..."
  
  local running_containers defined_projects orphan_count=0
  
  # Get running pocketbase containers
  running_containers=$(docker ps --filter "name=pocketbase_" --format "{{.Names}}" 2>/dev/null || true)
  
  # Get defined projects from compose file
  defined_projects=$(grep -oP 'pocketbase_\K[\w-]+' "$COMPOSE" 2>/dev/null || true)
  
  if [ -n "$running_containers" ]; then
    for container in $running_containers; do
      local project_name="${container#pocketbase_}"
      if ! echo "$defined_projects" | grep -qx "$project_name"; then
        log_warning "Stopping orphan container: $container"
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
        ((orphan_count++))
      fi
    done
  fi
  
  # Clean up unused images
  log_info "Cleaning up unused Docker resources..."
  docker system prune -f >/dev/null 2>&1 || true
  
  if [ $orphan_count -eq 0 ]; then
    log_success "No orphaned containers found"
  else
    log_success "Cleaned up $orphan_count orphaned container(s)"
  fi
}

start_service() {
  local NAME="$1"
  
  if [ "$NAME" == "all" ]; then
    log_info "Starting all services..."
    if $DOCKER_COMPOSE up -d --remove-orphans; then
      log_success "All services started successfully!"
    else
      log_error "Failed to start services"
      exit 1
    fi
  else
    validate_project_name "$NAME"
    
    if ! grep -q "pocketbase_${NAME}:" "$COMPOSE"; then
      log_error "Project '$NAME' not found."
      exit 1
    fi
    
    log_info "Starting service '$NAME'..."
    if $DOCKER_COMPOSE up -d "pocketbase_$NAME" nginx --remove-orphans; then
      log_success "Service '$NAME' started successfully!"
    else
      log_error "Failed to start service '$NAME'"
      exit 1
    fi
  fi
}

stop_service() {
  local NAME="$1"
  
  if [ "$NAME" == "all" ]; then
    log_info "Stopping all services..."
    if $DOCKER_COMPOSE stop; then
      log_success "All services stopped successfully!"
    else
      log_error "Failed to stop services"
      exit 1
    fi
  else
    validate_project_name "$NAME"
    
    if ! grep -q "pocketbase_${NAME}:" "$COMPOSE"; then
      log_error "Project '$NAME' not found."
      exit 1
    fi
    
    log_info "Stopping service '$NAME'..."
    if $DOCKER_COMPOSE stop "pocketbase_$NAME"; then
      log_success "Service '$NAME' stopped successfully!"
    else
      log_error "Failed to stop service '$NAME'"
      exit 1
    fi
  fi
}

restart_service() {
  local NAME="$1"
  
  if [ "$NAME" == "all" ]; then
    log_info "Restarting all services..."
    if $DOCKER_COMPOSE restart; then
      log_success "All services restarted successfully!"
    else
      log_error "Failed to restart services"
      exit 1
    fi
  else
    validate_project_name "$NAME"
    
    if ! grep -q "pocketbase_${NAME}:" "$COMPOSE"; then
      log_error "Project '$NAME' not found."
      exit 1
    fi
    
    log_info "Restarting service '$NAME'..."
    if $DOCKER_COMPOSE restart "pocketbase_$NAME" nginx; then
      log_success "Service '$NAME' restarted successfully!"
    else
      log_error "Failed to restart service '$NAME'"
      exit 1
    fi
  fi
}

# Main script execution
main() {
  # Change to script directory
  cd "$SCRIPT_DIR"
  
  # Check dependencies
  check_dependencies
  
  # Handle commands
  case "${1:-}" in
    add)
      [[ $# -ge 2 ]] || usage
      add_project "$2" "${3:-}"
      ;;
    remove)
      [[ $# -ge 2 ]] || usage
      remove_project "$2"
      ;;
    list)
      list_projects
      ;;
    start)
      [[ $# -ge 2 ]] || usage
      start_service "$2"
      ;;
    stop)
      [[ $# -ge 2 ]] || usage
      stop_service "$2"
      ;;
    restart)
      [[ $# -ge 2 ]] || usage
      restart_service "$2"
      ;;
    logs)
      [[ $# -ge 2 ]] || usage
      show_logs "$2"
      ;;
    status)
      show_status
      ;;
    build)
      build_image
      ;;
    cleanup)
      cleanup
      ;;
    *)
      usage
      ;;
  esac
}

# Run main function
main "$@"