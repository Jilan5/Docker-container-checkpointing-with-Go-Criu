![criu-config-external-mounts](https://github.com/user-attachments/assets/7650fe5d-a2f0-49a0-ae11-64cd3831f124)# Docker Container Checkpoint with Go-CRIU

## Introduction

This project demonstrates how to checkpoint Docker containers using CRIU (Checkpoint/Restore In Userspace). The implementation is a  Go application that can inspect and checkpoint running Docker containers, understanding the complete flow from Docker API integration to CRIU system calls.



## Objectives
By using this project, you will understand:

1. **Docker Container Internals**: How to inspect and extract container metadata
2. **CRIU Integration**: How to configure and use CRIU programmatically
3. **Mount Point Management**: How Docker's filesystem layers work with checkpointing
4. **Error Handling**: How to debug and troubleshoot checkpoint failures
5. **Production Deployment**: How to deploy and manage checkpoint systems

## Prerequisites

### System Requirements
- Ubuntu 20.04 or 22.04 (recommended)
- Minimum 2 CPU cores and 4GB RAM
- Docker with experimental features enabled
- CRIU (Checkpoint/Restore In Userspace)
- Go 1.19+
- Root/sudo privileges

### Knowledge Prerequisites
- Basic understanding of Docker containers
- Familiarity with Go programming
- Linux system administration basics
- Understanding of processes and namespaces

## Quick Setup

### Automated Setup (Recommended)

```bash
# Clone the repository
git clone https://github.com/Jilan5/Docker-container-checkpointing-with-Go-Criu.git
cd Docker-container-checkpointing-with-Go-Criu

# Run the automated setup script
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The setup script will:
1. Update system packages
2. Install Docker, CRIU, and Go if not present
3. Enable Docker experimental features
4. Build the checkpoint application
5. Add Go to your PATH
6. Run a simple test to verify everything works

### Manual Setup

If you prefer manual installation:

```bash
# Update system
sudo apt-get update
sudo apt-get install -y wget curl git build-essential

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker $USER

# Install CRIU
sudo apt-get install -y criu
sudo setcap cap_sys_admin,cap_sys_ptrace,cap_sys_chroot+ep $(which criu)

# Install Go
GO_VERSION="1.21.5"
wget "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Enable Docker experimental features
sudo mkdir -p /etc/docker
echo '{"experimental": true}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```
### Build the application
```bash
# Build the application
git clone https://github.com/Jilan5/Docker-container-checkpointing-with-Go-Criu.git
cd Docker-container-checkpointing-with-Go-Criu

go mod tidy
go build -o docker-checkpoint
```


### Basic Checkpoint

```bash
# Start a test container
docker run -d --name test-app alpine sh -c 'counter=0; while true; do echo "Count: $counter"; counter=$((counter + 1)); sleep 1; done'

# Checkpoint the container (leaves it running)
sudo ./docker-checkpoint -container test-app -name checkpoint1

# Check the checkpoint files
ls -la /tmp/docker-checkpoints/test-app/checkpoint1/
```

### Command Line Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `-container` | `string` | *required* | Container name or ID to checkpoint |
| `-name` | `string` | `checkpoint1` | Name for the checkpoint |
| `-dir` | `string` | `/tmp/docker-checkpoints` | Base directory for checkpoints |
| `-leave-running` | `boolean` | `true` | Leave container running after checkpoint |
| `-tcp` | `boolean` | `true` | Checkpoint established TCP connections |
| `-file-locks` | `boolean` | `true` | Checkpoint file locks |
| `-pre-dump` | `boolean` | `false` | Perform pre-dump for optimization |

**Usage:**
```bash
sudo ./docker-checkpoint -container <name> [options]
```

### Advanced Examples

```bash
# Checkpoint and stop the container
sudo ./docker-checkpoint -container myapp -leave-running=false

# Checkpoint with custom directory
sudo ./docker-checkpoint -container myapp -dir /opt/checkpoints

# Checkpoint with pre-dump optimization
sudo ./docker-checkpoint -container myapp -pre-dump=true

# Checkpoint a web server with TCP connections
docker run -d --name nginx -p 8080:80 nginx
sudo ./docker-checkpoint -container nginx -tcp=true
```

## Architecture & Implementation
### Part 1: Docker Container Inspection

The application needs to gather comprehensive container information before checkpointing:

```go
type ContainerInfo struct {
    ID         string                 // Short container ID
    Name       string                 // Container name
    PID        int                   // Main process PID
    State      string                // Container state
    RootFS     string                // Root filesystem path
    Runtime    string                // Container runtime (runc, etc.)
    BundlePath string                // OCI bundle path
    Namespaces map[string]string     // Process namespaces
    CgroupPath string                // Cgroup path
}
```

**Key Implementation Points:**

1. **Docker API Connection**: Use the official Docker Go client with environment-based configuration
2. **Container Validation**: Ensure the container is running before attempting checkpoint
3. **Namespace Discovery**: Map all container namespaces for CRIU
4. **Path Resolution**: Extract correct filesystem and bundle paths

### Part 2: CRIU Configuration

CRIU requires specific configuration for Docker containers:

![Uploa<svg id="diagram4" viewBox="0 0 1000 900" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <marker id="arrowhead4" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
                        <polygon points="0 0, 10 3, 0 6" fill="#666"/>
                    </marker>
                </defs>
                
                <rect x="350" y="20" width="300" height="80" fill="#42a5f5" stroke="#1976d2" class="box" rx="5"/>
                <text x="500" y="50" text-anchor="middle" fill="white" class="title-text">🐳 Running Docker Container</text>
                <text x="500" y="70" text-anchor="middle" fill="white" class="small-text">Filesystem Layers + Process</text>
                
                <rect x="50" y="150" width="400" height="250" fill="#f3e5f5" stroke="#7b1fa2" class="box" rx="5"/>
                <text x="250" y="175" text-anchor="middle" fill="#7b1fa2" class="title-text">CRIU Configuration (criuOpts)</text>
                
                <text x="70" y="205" class="small-text">• Pid: target process ID</text>
                <text x="70" y="230" class="small-text">• LogLevel: 4 (verbose)</text>
                <text x="70" y="255" class="small-text">• Root: container filesystem path</text>
                <text x="70" y="280" class="small-text">• ManageCgroups: true</text>
                <text x="70" y="305" class="small-text">• ShellJob: true (for Docker)</text>
                <text x="70" y="330" class="small-text">• LeaveRunning: configurable</text>
                <text x="70" y="355" class="small-text">• ImagesDirectory: checkpoint path</text>
                <text x="70" y="380" class="small-text">• External: [...mounts marked external]</text>
                
                <rect x="550" y="150" width="400" height="250" fill="#fff3e0" stroke="#f57c00" class="box" rx="5"/>
                <text x="750" y="175" text-anchor="middle" fill="#f57c00" class="title-text">External Mounts (Excluded)</text>
                
                <rect x="570" y="195" width="360" height="30" fill="#ffe0b2" stroke="#e65100" class="box" rx="3"/>
                <text x="750" y="215" text-anchor="middle" class="small-text">❌ /proc (process filesystem)</text>
                
                <rect x="570" y="230" width="360" height="30" fill="#ffe0b2" stroke="#e65100" class="box" rx="3"/>
                <text x="750" y="250" text-anchor="middle" class="small-text">❌ /dev (device filesystem)</text>
                
                <rect x="570" y="265" width="360" height="30" fill="#ffe0b2" stroke="#e65100" class="box" rx="3"/>
                <text x="750" y="285" text-anchor="middle" class="small-text">❌ /sys (system filesystem)</text>
                
                <rect x="570" y="300" width="360" height="30" fill="#ffe0b2" stroke="#e65100" class="box" rx="3"/>
                <text x="750" y="320" text-anchor="middle" class="small-text">❌ /etc/hostname, /etc/hosts, /etc/resolv.conf</text>
                
                <rect x="570" y="335" width="360" height="30" fill="#ffe0b2" stroke="#e65100" class="box" rx="3"/>
                <text x="750" y="355" text-anchor="middle" class="small-text">❌ /sys/fs/cgroup (cgroup filesystem)</text>
                
                <text x="750" y="385" text-anchor="middle" class="small-text" fill="#e65100" font-style="italic">These mounts are NOT checkpointed</text>
                
                <rect x="200" y="470" width="600" height="380" fill="#e8f5e9" stroke="#388e3c" class="box" rx="5"/>
                <text x="500" y="495" text-anchor="middle" fill="#388e3c" class="title-text">Checkpoint Output Files</text>
                <text x="500" y="515" text-anchor="middle" class="small-text" fill="#388e3c">(Generated in checkpoint directory)</text>
                
                <rect x="220" y="540" width="250" height="40" fill="#c8e6c9" stroke="#388e3c" class="box" rx="3"/>
                <text x="345" y="565" text-anchor="middle" class="small-text">core-*.img (process state)</text>
                
                <rect x="530" y="540" width="250" height="40" fill="#c8e6c9" stroke="#388e3c" class="box" rx="3"/>
                <text x="655" y="565" text-anchor="middle" class="small-text">pages-*.img (memory pages)</text>
                
                <rect x="220" y="590" width="250" height="40" fill="#c8e6c9" stroke="#388e3c" class="box" rx="3"/>
                <text x="345" y="615" text-anchor="middle" class="small-text">pagemap-*.img (memory map)</text>
                
                <rect x="530" y="590" width="250" height="40" fill="#c8e6c9" stroke="#388e3c" class="box" rx="3"/>
                <text x="655" y="615" text-anchor="middle" class="small-text">fdinfo-*.img (file descriptors)</text>
                
                <rect x="220" y="640" width="250" height="40" fill="#c8e6c9" stroke="#388e3c" class="box" rx="3"/>
                <text x="345" y="665" text-anchor="middle" class="small-text">mountpoints-*.img (mount info)</text>
                
                <rect x="530" y="640" width="250" height="40" fill="#c8e6c9" stroke="#388e3c" class="box" rx="3"/>
                <text x="655" y="665" text-anchor="middle" class="small-text">netdev-*.img (network state)</text>
                
                <rect x="220" y="690" width="250" height="40" fill="#a5d6a7" stroke="#388e3c" class="box" rx="3"/>
                <text x="345" y="715" text-anchor="middle" class="small-text">container.json (metadata)</text>
                
                <rect x="530" y="690" width="250" height="40" fill="#a5d6a7" stroke="#388e3c" class="box" rx="3"/>
                <text x="655" y="715" text-anchor="middle" class="small-text">dump.log (CRIU logs)</text>
                
                <rect x="220" y="750" width="560" height="80" fill="#fff" stroke="#388e3c" class="box" rx="3" stroke-dasharray="5,5"/>
                <text x="500" y="775" text-anchor="middle" class="small-text" font-weight="bold">Complete checkpoint can be restored later</text>
                <text x="500" y="795" text-anchor="middle" class="small-text">All container state saved except external mounts</text>
                <text x="500" y="815" text-anchor="middle" class="small-text">(which will be re-mounted during restore)</text>
                
                <path d="M 500 100 L 250 150" stroke="#666" class="arrow" marker-end="url(#arrowhead4)"/>
                <path d="M 450 380 L 450 470" stroke="#666" class="arrow" marker-end="url(#arrowhead4)"/>
                <path d="M 450 275 L 550 275" stroke="#666" class="arrow" marker-end="url(#arrowhead4)" stroke-dasharray="5,5"/>
                
                <text x="350" y="125" text-anchor="middle" class="small-text" fill="#666">configure</text>
                <text x="420" y="430" text-anchor="middle" class="small-text" fill="#666">execute dump →</text>
                <text x="420" y="445" text-anchor="middle" class="small-text" fill="#666">generates files</text>
                <text x="500" y="265" text-anchor="middle" class="small-text" fill="#f57c00">mark as external</text>
            </svg>ding criu-config-external-mounts.svg…]()

```go
criuOpts := &rpc.CriuOpts{
    Pid:            proto.Int32(int32(info.PID)),
    LogLevel:       proto.Int32(4),           // Verbose logging
    LogFile:        proto.String("dump.log"),
    Root:           proto.String(info.RootFS),
    ManageCgroups:  proto.Bool(true),         // Handle cgroups
    TcpEstablished: proto.Bool(true),         // Checkpoint TCP connections
    FileLocks:      proto.Bool(true),         // Handle file locks
    LeaveRunning:   proto.Bool(true),         // Keep container running
    ShellJob:       proto.Bool(true),         // Required for docker run containers
}
```

**Critical Configuration:**

1. **External Mounts**: Docker uses bind mounts that must be marked as external
2. **Cgroup Management**: CRIU must understand Docker's cgroup hierarchy
3. **Namespace Handling**: All container namespaces must be properly configured
4. **Filesystem Root**: Set the correct container root filesystem

### Part 3: Mount Point Handling

Docker containers have complex mount structures that require special handling:

```go
External: []string{
    "mnt[/proc]:proc",              // Process filesystem
    "mnt[/dev]:dev",                // Device filesystem
    "mnt[/sys]:sys",                // System filesystem
    "mnt[/dev/shm]:shm",            // Shared memory
    "mnt[/dev/pts]:pts",            // Pseudo terminals
    "mnt[/dev/mqueue]:mqueue",      // Message queues
    "mnt[/etc/hostname]:hostname",   // Docker bind mounts
    "mnt[/etc/hosts]:hosts",        // Docker bind mounts
    "mnt[/etc/resolv.conf]:resolv.conf", // DNS configuration
    "mnt[/sys/fs/cgroup]:cgroup",   // Cgroup filesystem
}
```

**Mount Strategy:**
- **External Mounts**: Mark system and Docker-managed mounts as external
- **Bind Mounts**: Handle Docker's special bind mounts for networking
- **Overlays**: Work with Docker's overlay filesystem layers

## Implementation Walkthrough

### Step 1: Container Discovery and Validation

```go
func inspectContainer(containerName string) (*ContainerInfo, error) {
    ctx := context.Background()
    cli, err := client.NewClientWithOpts(client.FromEnv)
    if err != nil {
        return nil, fmt.Errorf("failed to create docker client: %w", err)
    }

    if err != nil {
        return nil, fmt.Errorf("failed to inspect container: %w", err)
    }

    if !containerJSON.State.Running {
        return nil, fmt.Errorf("container %s is not running", containerName)
    }

    // Extract and validate container information...
}
```

### Step 2: CRIU Configuration and Execution

```go
func doCRIUCheckpoint(info *ContainerInfo, checkpointDir string, opts Options) error {
    criuClient := criu.MakeCriu()
    criuClient.SetCriuPath("criu")

    // Configure CRIU options...
    criuOpts := &rpc.CriuOpts{
        // Configuration as shown above...
    }

    // Set working directory
    workDir, err := os.Open(checkpointDir)
    if err != nil {
        return fmt.Errorf("failed to open checkpoint directory: %w", err)
    }
    defer workDir.Close()

    criuOpts.ImagesDirFd = proto.Int32(int32(workDir.Fd()))

    // Execute checkpoint
    if err := criuClient.Dump(criuOpts, nil); err != nil {
        // Handle errors with detailed logging...
    }
}
```

### Step 3: Metadata Persistence

```go
func saveMetadata(info *ContainerInfo, checkpointDir string) error {
    metadata := map[string]interface{}{
        "id":          info.ID,
        "name":        info.Name,
        "runtime":     info.Runtime,
        "rootfs":      info.RootFS,
        "bundle_path": info.BundlePath,
        "namespaces":  info.Namespaces,
        "cgroup_path": info.CgroupPath,
        "timestamp":   time.Now().Format(time.RFC3339),
    }

    metadataFile := filepath.Join(checkpointDir, "container.json")
    file, err := os.Create(metadataFile)
    if err != nil {
        return err
    }
    defer file.Close()

    encoder := json.NewEncoder(file)
    encoder.SetIndent("", "  ")
    return encoder.Encode(metadata)
}
```

## Understanding Checkpoint Files

After a successful checkpoint, you'll find these files:

| File | Purpose |
|------|---------|
| `core-*.img` | Process core information and registers |
| `pages-*.img` | Memory page contents |
| `pagemap-*.img` | Memory page mappings |
| `fdinfo-*.img` | File descriptor information |
| `mountpoints-*.img` | Mount point information |
| `netdev-*.img` | Network device state |
| `container.json` | Container metadata (custom) |
| `dump.log` | CRIU operation log |

## Testing

### Automated Testing

Run the comprehensive test suite:
```bash
chmod +x scripts/test.sh
sudo ./scripts/test.sh
```

This will:
1. Start various test containers (Alpine, Nginx, Python apps)
2. Attempt to checkpoint them with different configurations
3. Verify checkpoint files are created and valid
4. Test error handling and edge cases
5. Clean up test containers and checkpoints

### Manual Testing

Test with different container types:

```bash
# Simple Alpine container
docker run -d --name test-simple alpine sleep 3600
sudo ./docker-checkpoint -container test-simple

# Container with network service
docker run -d --name test-nginx -p 8080:80 nginx
sudo ./docker-checkpoint -container test-nginx

# Container with mounted volumes
docker run -d --name test-volume -v /tmp:/data alpine sh -c 'while true; do date > /data/timestamp; sleep 1; done'
sudo ./docker-checkpoint -container test-volume
```

## Troubleshooting

### Common Issues

#### 1. Permission Denied
```bash
# Ensure CRIU has proper capabilities
sudo setcap cap_sys_admin,cap_sys_ptrace,cap_sys_chroot+ep $(which criu)

# Run with sudo
sudo ./docker-checkpoint -container myapp
```

#### 2. Docker Experimental Features
```bash
# Verify experimental features are enabled
docker version | grep Experimental

# If not enabled, run:
sudo mkdir -p /etc/docker
echo '{"experimental": true}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

#### 3. Mount Point Errors
The application handles most Docker mount issues automatically. If you encounter mount errors, check the CRIU log:
```bash
cat /tmp/docker-checkpoints/<container>/<checkpoint>/dump.log
```

#### 4. Container Not Found
```bash
# List running containers
docker ps

# Use exact container name or ID
sudo ./docker-checkpoint -container exact_name
```

### Debug Mode

For detailed debugging, examine the CRIU log file:
```bash
# View recent checkpoint log
tail -f /tmp/docker-checkpoints/<container>/<checkpoint>/dump.log
```

## Common Challenges and Solutions

### Challenge 1: Mount Point Complexity

**Problem**: Docker's complex mount structure causes CRIU failures

**Solution**:
- Analyze mount structure with `docker inspect`
- Use external mount configuration for Docker-managed mounts
- Test mount handling with different container configurations

### Challenge 2: Cgroup Management

**Problem**: CRIU fails to handle Docker's cgroup hierarchy

**Solution**:
- Configure `ManageCgroups: true`
- Set proper cgroup root paths
- Handle both v1 and v2 cgroup configurations

### Challenge 3: Process Tree Complexity

**Problem**: Multi-process containers may have complex process trees

**Solution**:
- Use `ShellJob: true` for containers started with `docker run`
- Handle process hierarchies correctly
- Test with applications that spawn child processes

### Challenge 4: Network State

**Problem**: Network connections may prevent successful checkpoint

**Solution**:
- Configure `TcpEstablished: true` for network services
- Handle external network dependencies
- Test with various network configurations

## Security Considerations

- **Root Privileges**: This tool requires root/sudo for CRIU operations
- **Memory Contents**: Checkpoint files contain full memory dumps
- **Storage**: Store checkpoints securely with appropriate access controls
- **Cleanup**: Regularly clean old checkpoint files

## Limitations

- **Container Types**: Works with standard Docker containers
- **External Dependencies**: Some applications may have external state not captured
- **Network**: Complex network configurations may need additional handling
- **Volumes**: Persistent volumes are not checkpointed

## Resources

- [CRIU Documentation](https://criu.org/Documentation)
- [Docker Checkpoint Documentation](https://docs.docker.com/engine/reference/commandline/checkpoint/)
- [Go CRIU Library](https://github.com/checkpoint-restore/go-criu)
- [Container Runtime Specification](https://github.com/opencontainers/runtime-spec)

