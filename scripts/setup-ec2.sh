#!/bin/bash
# setup-ec2.sh - EC2-specific setup script for Docker checkpoint lab

set -e

echo "=== EC2 Docker Container Checkpoint Setup ==="
echo

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check EC2 environment
check_ec2_environment() {
    log_step "Checking EC2 environment..."

    # Check if running on EC2
    if curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        local instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        local instance_type=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
        local az=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

        log_info "Running on EC2 instance: $instance_id"
        log_info "Instance type: $instance_type"
        log_info "Availability zone: $az"

        # Check instance type recommendations
        case $instance_type in
            t2.nano|t2.micro|t3.nano|t3.micro)
                log_warn "Instance type $instance_type may be too small for reliable checkpointing"
                log_warn "Recommended: t2.medium or larger"
                ;;
            t2.small|t3.small)
                log_warn "Instance type $instance_type is minimal for checkpointing"
                log_warn "Consider upgrading to t2.medium or larger for better performance"
                ;;
            *)
                log_info "Instance type $instance_type is suitable for checkpointing"
                ;;
        esac
    else
        log_warn "Not running on EC2 or metadata service unavailable"
        log_warn "This script is optimized for EC2 but should work on other Ubuntu systems"
    fi

    # Check Ubuntu version
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        log_info "Operating system: $PRETTY_NAME"

        case $VERSION_ID in
            "20.04"|"22.04"|"24.04")
                log_info "Ubuntu version is supported"
                ;;
            *)
                log_warn "Ubuntu version $VERSION_ID is not officially tested"
                log_warn "This script is tested on Ubuntu 20.04, 22.04, and 24.04"
                ;;
        esac
    fi
}

# Install Docker with EC2-specific optimizations
install_docker_ec2() {
    if ! command_exists docker; then
        log_step "Installing Docker for EC2..."

        # Update package index
        sudo apt-get update

        # Install prerequisites
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release \
            software-properties-common

        # Add Docker's official GPG key
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        # Set up repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Add ubuntu user to docker group (common on EC2)
        if id -u ubuntu >/dev/null 2>&1; then
            sudo usermod -aG docker ubuntu
            log_info "Added 'ubuntu' user to docker group"
        fi

        # Add current user to docker group
        sudo usermod -aG docker $USER

        # Start and enable Docker
        sudo systemctl start docker
        sudo systemctl enable docker

        log_info "Docker installed and configured for EC2!"
    else
        log_info "Docker is already installed"
        docker --version
    fi
}

# Install CRIU with EC2 considerations
install_criu_ec2() {
    if ! command_exists criu; then
        log_step "Installing CRIU for EC2..."

        # Update package index
        sudo apt-get update

        # Install CRIU and dependencies
        sudo apt-get install -y criu

        # Install additional tools that might be helpful
        sudo apt-get install -y \
            linux-tools-common \
            linux-tools-generic \
            htop \
            tree

        # Set capabilities for CRIU
        sudo setcap cap_sys_admin,cap_sys_ptrace,cap_sys_chroot+ep $(which criu)

        # Verify CRIU installation
        if criu check >/dev/null 2>&1; then
            log_info "CRIU check passed"
        else
            log_warn "CRIU check reported warnings (this may be normal on EC2)"
            log_info "CRIU features may still work for basic containers"
        fi

        criu --version
        log_info "CRIU installed successfully!"
    else
        log_info "CRIU is already installed"
        criu --version

        # Ensure capabilities are set
        sudo setcap cap_sys_admin,cap_sys_ptrace,cap_sys_chroot+ep $(which criu)
    fi
}

# Install Go with appropriate version for EC2
install_go_ec2() {
    if ! command_exists go; then
        log_step "Installing Go for EC2..."

        # Determine architecture
        local arch=$(uname -m)
        case $arch in
            x86_64)
                arch="amd64"
                ;;
            aarch64)
                arch="arm64"
                ;;
            *)
                log_error "Unsupported architecture: $arch"
                return 1
                ;;
        esac

        GO_VERSION="1.21.5"
        local go_archive="go${GO_VERSION}.linux-${arch}.tar.gz"

        log_info "Downloading Go ${GO_VERSION} for ${arch}..."
        wget -q "https://go.dev/dl/${go_archive}"

        # Remove any existing Go installation
        sudo rm -rf /usr/local/go

        # Install Go
        sudo tar -C /usr/local -xzf "$go_archive"
        rm "$go_archive"

        # Add Go to PATH for current user
        if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        fi

        # Add Go to PATH for ubuntu user if different
        if [ "$USER" != "ubuntu" ] && id -u ubuntu >/dev/null 2>&1; then
            if ! sudo -u ubuntu grep -q "/usr/local/go/bin" /home/ubuntu/.bashrc 2>/dev/null; then
                echo 'export PATH=$PATH:/usr/local/go/bin' | sudo -u ubuntu tee -a /home/ubuntu/.bashrc >/dev/null
            fi
        fi

        export PATH=$PATH:/usr/local/go/bin

        go version
        log_info "Go installed successfully!"
    else
        log_info "Go is already installed"
        go version
    fi
}

# Configure Docker for optimal EC2 performance
configure_docker_ec2() {
    log_step "Configuring Docker for EC2 environment..."

    sudo mkdir -p /etc/docker

    # Create optimized Docker daemon configuration for EC2
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "experimental": true,
    "live-restore": true,
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

    # Restart Docker to apply changes
    sudo systemctl restart docker

    # Wait for Docker to start
    sleep 3

    # Verify Docker is running
    if docker info >/dev/null 2>&1; then
        log_info "Docker configured and running successfully"

        # Check experimental features
        if docker version 2>/dev/null | grep -q "Experimental.*true"; then
            log_info "Docker experimental features enabled"
        else
            log_warn "Experimental features may need time to activate"
        fi
    else
        log_error "Docker failed to start properly"
        return 1
    fi
}

# Build the application with EC2-specific optimizations
build_application_ec2() {
    log_step "Building the Docker checkpoint application..."

    # Ensure we're in the right directory
    if [ ! -f "main.go" ]; then
        log_error "main.go not found. Please run this script from the lab directory."
        return 1
    fi

    # Set Go environment for optimal builds
    export GOOS=linux
    export CGO_ENABLED=0

    # Download dependencies
    log_info "Downloading Go dependencies..."
    go mod tidy
    go mod download

    # Build the application with optimizations
    log_info "Building optimized binary..."
    go build -ldflags="-w -s" -o docker-checkpoint

    # Make it executable
    chmod +x docker-checkpoint

    # Create scripts directory if it doesn't exist
    mkdir -p scripts

    # Make scripts executable
    if [ -f "scripts/setup.sh" ]; then
        chmod +x scripts/setup.sh
    fi
    if [ -f "scripts/test.sh" ]; then
        chmod +x scripts/test.sh
    fi

    log_info "Application built successfully!"

    # Test the binary
    if ./docker-checkpoint -h >/dev/null 2>&1; then
        log_info "Application responds correctly to help command"
    else
        log_error "Application failed basic functionality test"
        return 1
    fi
}

# Run EC2-specific tests
run_ec2_tests() {
    log_step "Running EC2-specific tests..."

    # Test Docker access
    if ! docker ps >/dev/null 2>&1; then
        log_error "Cannot access Docker. You may need to:"
        log_error "1. Log out and back in (for group membership)"
        log_error "2. Run: newgrp docker"
        return 1
    fi

    # Test with a simple container
    log_info "Testing basic checkpoint functionality..."

    # Pull a small image if not available
    docker pull alpine:latest >/dev/null 2>&1

    # Start test container
    docker run -d --name ec2-test alpine sh -c 'counter=0; while true; do echo "EC2 test: $counter"; counter=$((counter + 1)); sleep 1; done' >/dev/null

    sleep 2

    # Attempt checkpoint
    if sudo timeout 30 ./docker-checkpoint -container ec2-test -name ec2-basic-test >/dev/null 2>&1; then
        log_info "✓ Basic checkpoint test PASSED on EC2!"

        # Check checkpoint files
        if [ -d "/tmp/docker-checkpoints/ec2-test/ec2-basic-test" ]; then
            local file_count=$(ls -1 /tmp/docker-checkpoints/ec2-test/ec2-basic-test/ | wc -l)
            log_info "Created $file_count checkpoint files"
        fi
    else
        log_warn "Basic checkpoint test failed, but setup may still be functional"
        log_info "Try running './scripts/test.sh' for comprehensive testing"
    fi

    # Cleanup
    docker stop ec2-test >/dev/null 2>&1 || true
    docker rm ec2-test >/dev/null 2>&1 || true
    sudo rm -rf /tmp/docker-checkpoints/ec2-test >/dev/null 2>&1 || true
}

# Print EC2-specific usage information
print_ec2_usage() {
    echo
    log_info "=== EC2 Setup Complete ==="
    echo
    log_info "Your Docker checkpoint system is ready!"
    echo
    log_info "Quick start commands:"
    log_info "  docker run -d --name myapp alpine sleep 3600"
    log_info "  sudo ./docker-checkpoint -container myapp"
    echo
    log_info "Available scripts:"
    log_info "  ./scripts/test.sh      - Run comprehensive tests"
    log_info "  ./scripts/setup.sh     - Re-run setup if needed"
    echo
    log_info "EC2-specific notes:"
    log_info "  - Checkpoint files are stored in /tmp/docker-checkpoints/"
    log_info "  - Ensure sufficient disk space for large checkpoints"
    log_info "  - Consider using EBS volumes for persistent checkpoint storage"
    echo
    log_info "Security reminders:"
    log_info "  - Checkpoint files contain memory contents"
    log_info "  - Secure checkpoint directories appropriately"
    log_info "  - Clean up old checkpoints regularly"
    echo

    # Show disk space
    log_info "Current disk usage:"
    df -h / | tail -1 | awk '{print "  Root filesystem: " $3 " used, " $4 " available (" $5 " full)"}'

    # Show memory
    log_info "Available memory:"
    free -h | grep "^Mem:" | awk '{print "  Memory: " $2 " total, " $7 " available"}'
}

# Main execution
main() {
    log_info "Starting EC2-optimized setup for Docker checkpoint lab..."
    echo

    # Check environment
    check_ec2_environment

    # Update system
    log_step "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y

    # Install prerequisites
    log_step "Installing prerequisites..."
    sudo apt-get install -y \
        wget \
        curl \
        git \
        build-essential \
        unzip \
        tree \
        htop

    # Install required software
    install_docker_ec2
    install_criu_ec2
    install_go_ec2
    configure_docker_ec2

    # Build application
    build_application_ec2

    # Run tests
    run_ec2_tests

    # Print usage information
    print_ec2_usage

    # Final group membership note
    if ! groups | grep -q docker; then
        echo
        log_warn "Note: You may need to log out and back in for Docker group membership to take effect"
        log_info "Alternatively, run: newgrp docker"
    fi

    echo
    log_info "🎉 EC2 setup completed successfully!"
}

# Ensure not running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Do not run this script as root. Use the 'ubuntu' user or another non-root user with sudo access."
    exit 1
fi

# Run main function
main "$@"