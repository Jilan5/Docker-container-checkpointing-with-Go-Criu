#!/bin/bash
# setup.sh - Universal setup script for Docker checkpoint lab

set -e

echo "=== Docker Container Checkpoint Lab Setup ==="
echo

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    log_warn "Running as root. This script will add current user to docker group."
    log_warn "Consider running as a regular user with sudo access."
fi

# Install Docker if not present
install_docker() {
    if ! command_exists docker; then
        log_info "Installing Docker..."

        # Update package index
        sudo apt-get update

        # Install required packages
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

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

        # Add user to docker group
        sudo usermod -aG docker $USER

        log_info "Docker installed successfully!"
        log_warn "You may need to log out and back in for group changes to take effect"
    else
        log_info "Docker is already installed"
        docker --version
    fi
}

# Install CRIU
install_criu() {
    if ! command_exists criu; then
        log_info "Installing CRIU..."

        sudo apt-get update
        sudo apt-get install -y criu

        # Set capabilities for CRIU
        sudo setcap cap_sys_admin,cap_sys_ptrace,cap_sys_chroot+ep $(which criu)

        # Verify installation
        criu --version
        log_info "CRIU installed successfully!"
    else
        log_info "CRIU is already installed"
        criu --version

        # Ensure capabilities are set
        sudo setcap cap_sys_admin,cap_sys_ptrace,cap_sys_chroot+ep $(which criu)
    fi
}

# Install Go if not present
install_go() {
    if ! command_exists go; then
        log_info "Installing Go..."

        GO_VERSION="1.21.5"
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
        rm "go${GO_VERSION}.linux-amd64.tar.gz"

        # Add Go to PATH
        if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        fi
        export PATH=$PATH:/usr/local/go/bin

        go version
        log_info "Go installed successfully!"
    else
        log_info "Go is already installed"
        go version
    fi
}

# Enable Docker experimental features
enable_docker_experimental() {
    log_info "Enabling Docker experimental features..."

    sudo mkdir -p /etc/docker

    # Create or update Docker daemon configuration
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "experimental": true,
    "live-restore": true
}
EOF

    # Restart Docker to apply changes
    sudo systemctl restart docker

    # Verify experimental features
    sleep 2
    if docker version 2>/dev/null | grep -q "Experimental.*true"; then
        log_info "Docker experimental features enabled successfully!"
    else
        log_warn "Could not verify experimental features. They may need time to take effect."
    fi
}

# Build the checkpoint application
build_application() {
    log_info "Building the Docker checkpoint application..."

    # Ensure we're in the right directory
    if [ ! -f "main.go" ]; then
        log_error "main.go not found. Please run this script from the lab directory."
        exit 1
    fi

    # Download dependencies and create go.sum
    go mod tidy
    go mod download

    # Build the application
    go build -o docker-checkpoint

    # Make it executable
    chmod +x docker-checkpoint

    log_info "Application built successfully!"
}

# Run a simple test
run_test() {
    log_info "Running a basic functionality test..."

    # Test Docker access
    if ! docker ps >/dev/null 2>&1; then
        log_error "Cannot access Docker. You may need to:"
        log_error "1. Log out and back in (for group membership)"
        log_error "2. Start Docker daemon: sudo systemctl start docker"
        return 1
    fi

    # Test CRIU access
    if ! sudo criu check >/dev/null 2>&1; then
        log_warn "CRIU check failed. Some features may not work properly."
    fi

    # Test the application help
    if ./docker-checkpoint -h >/dev/null 2>&1; then
        log_info "Application responds correctly!"
    else
        log_error "Application failed to respond to help command"
        return 1
    fi

    # Quick container test
    log_info "Testing with a simple container..."

    docker run -d --name test-setup alpine sleep 10 >/dev/null 2>&1
    sleep 1

    if sudo timeout 30 ./docker-checkpoint -container test-setup -name test-run >/dev/null 2>&1; then
        log_info "Basic checkpoint test PASSED!"
    else
        log_warn "Basic checkpoint test failed, but setup is complete."
        log_warn "Check the troubleshooting section in README.md"
    fi

    # Cleanup
    docker stop test-setup >/dev/null 2>&1 || true
    docker rm test-setup >/dev/null 2>&1 || true
    rm -rf /tmp/docker-checkpoints/test-setup >/dev/null 2>&1 || true
}

# Main execution
main() {
    log_info "Starting setup for Docker checkpoint lab..."
    log_info "This script will install Docker, CRIU, and Go if they're not present"
    echo

    # Check for Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        log_warn "This script is designed for Ubuntu. It may work on other Debian-based systems."
    fi

    # Update system packages
    log_info "Updating system packages..."
    sudo apt-get update

    # Install prerequisites
    sudo apt-get install -y wget curl git build-essential

    # Install required software
    install_docker
    install_criu
    install_go
    enable_docker_experimental

    # Build the application
    echo
    log_info "Setting up the checkpoint application..."
    build_application

    echo
    log_info "=== Setup Complete ==="
    echo
    log_info "You can now use the checkpoint tool:"
    log_info "  sudo ./docker-checkpoint -container <container-name>"
    echo
    log_info "Quick start:"
    log_info "  1. Start a container: docker run -d --name myapp alpine sleep 3600"
    log_info "  2. Checkpoint it: sudo ./docker-checkpoint -container myapp"
    log_info "  3. Check results: ls -la /tmp/docker-checkpoints/myapp/"
    echo
    log_info "Run './scripts/test.sh' for comprehensive testing"
    echo

    # Optionally run a test
    read -p "Do you want to run a quick test? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_test
    fi

    echo
    log_info "Setup completed successfully! 🎉"

    if groups $USER | grep -q docker; then
        log_info "You can now use Docker without sudo"
    else
        log_warn "You may need to log out and back in for Docker group membership to take effect"
    fi
}

# Run main function
main "$@"