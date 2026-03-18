# BeeGFS Relatime Patch

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![BeeGFS 7.4.6](https://img.shields.io/badge/BeeGFS-7.4.6-blue.svg)](#supported-versions)
[![BeeGFS 8.2.2](https://img.shields.io/badge/BeeGFS-8.2.2-blue.svg)](#supported-versions)

Patch files for BeeGFS client to enable atime updates on read-only operations using relatime semantics.

## Table of Contents

- [BeeGFS Relatime Patch](#beegfs-relatime-patch)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Supported Versions](#supported-versions)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [Automated Installation](#automated-installation)
      - [Basic Installation](#basic-installation)
      - [Installation Options](#installation-options)
      - [Expected Output](#expected-output)
    - [Manual Installation](#manual-installation)
  - [Uninstallation](#uninstallation)
    - [Automated Uninstallation](#automated-uninstallation)
    - [Manual Uninstallation](#manual-uninstallation)
  - [Configuration](#configuration)
    - [Relatime Threshold Configuration](#relatime-threshold-configuration)
  - [Performance Impact](#performance-impact)
  - [Verification](#verification)
    - [Verify Patch Installation](#verify-patch-installation)
  - [Container and Build Environments](#container-and-build-environments)
    - [Supported Environments](#supported-environments)
    - [Automatic Detection](#automatic-detection)
    - [Manual Control](#manual-control)

## Overview

By default, BeeGFS client does not update file access times (atime) on read-only operations for performance reasons. This patch modifies the client to update atimes using relatime semantics, where atimes are updated on read-only operations if:

- The previous atime is older than the mtime or ctime, OR
- The previous atime is older than a configurable threshold (`tuneRelatimeSecs`) from the current time

This provides accurate atime tracking for applications that depend on access time information while maintaining good performance characteristics.

## Supported Versions

| BeeGFS Version | Patch File                    |
|----------------|-------------------------------|
| 7.4.6          | `beegfs-7.4.6-relatime.patch` |
| 8.2.2          | `beegfs-8.2.2-relatime.patch` |

## Prerequisites

- **Operating System**: RHEL-based distributions (RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora)
- **Privileges**: Root access required
- **BeeGFS Client**: Must be installed and available via RPM
- **Build Tools**: Development tools for kernel module compilation

## Installation

### Automated Installation

The automated installer provides the most convenient installation method with comprehensive error handling and environment detection.

#### Basic Installation

```bash
git clone https://github.com/jeburks2/beegfs-relatime-patch.git
cd beegfs-relatime-patch
chmod +x install.sh
sudo ./install.sh
```

#### Installation Options

```bash
# View help and all available options
sudo ./install.sh --help

# Install patch but skip automatic rebuild (useful for CI/build environments)
sudo ./install.sh --norebuild

# Install in container/chroot (automatically detected, but no rebuild performed)
sudo ./install.sh
```

#### Expected Output

```bash
Checking system compatibility...
✓ Detected RHEL-based distribution: rocky
Detecting BeeGFS client version...
✓ Found BeeGFS client version: 8.2.2
Locating BeeGFS client source directory...
✓ BeeGFS client version 8 detected
Checking for patch file...
✓ Found patch file: beegfs-8.2.2-relatime.patch
✓ BeeGFS client service is currently running
Applying BeeGFS relatime patch for version 8.2.2...
✓ Patch applied successfully
Rebuilding the BeeGFS client...
✓ BeeGFS client rebuilt successfully
Restarting BeeGFS client service...
✓ BeeGFS client service restarted successfully
✓ BeeGFS relatime patch installation completed successfully!
```

### Manual Installation

For advanced users or custom deployment scenarios:

1. **Download the appropriate patch file** for your BeeGFS client version

2. **Navigate to the BeeGFS client source directory**:

   ```bash
   # For BeeGFS 8.x
   cd /opt/beegfs/src/client/client_module_8
   
   # For BeeGFS 7.x  
   cd /opt/beegfs/src/client/client_module_7
   ```

3. **Apply the patch**:

   ```bash
   patch -p1 --forward --batch < /path/to/beegfs-VERSION-relatime.patch
   ```

4. **Rebuild the BeeGFS client**:

   ```bash
   /opt/beegfs/sbin/beegfs-client rebuild
   ```

5. **Restart the BeeGFS client service**:

   ```bash
   systemctl restart beegfs-client
   ```

## Uninstallation

### Automated Uninstallation

```bash
# Navigate to the patch directory
cd beegfs-relatime-patch

# Remove the patch
sudo ./install.sh --uninstall

# Remove patch but skip automatic rebuild
sudo ./install.sh --uninstall --norebuild
```

### Manual Uninstallation

1. **Navigate to the BeeGFS client source directory**:

   ```bash
   # For BeeGFS 8.x
   cd /opt/beegfs/src/client/client_module_8
   
   # For BeeGFS 7.x
   cd /opt/beegfs/src/client/client_module_7
   ```

2. **Reverse the patch**:

   ```bash
   patch -p1 --reverse --batch < /path/to/beegfs-VERSION-relatime.patch
   ```

3. **Rebuild the BeeGFS client**:

   ```bash
   /opt/beegfs/sbin/beegfs-client rebuild
   ```

4. **Restart the BeeGFS client service**:

   ```bash
   systemctl restart beegfs-client
   ```

## Configuration

### Relatime Threshold Configuration

The patch adds a `tuneRelatimeSecs` parameter to control the atime update behavior.

**Default value**: `86400` seconds (24 hours)

**Configuration location**: `/etc/beegfs/beegfs-client.conf`

```ini
# Add this line to your beegfs-client.conf
tuneRelatimeSecs = 86400
```

**Configuration options**:

- `0`: Update atime on every read (equivalent to `atime` mount option)
- `> 0`: Update atime only if current atime is older than specified seconds
- Default `86400`: Update atime if older than 24 hours

After modifying the configuration, restart the BeeGFS client:

```bash
systemctl restart beegfs-client
```

## Performance Impact

Performance testing shows minimal impact on read-only workloads:

**Test methodology**: Measured time to process 100,000 ImageNet dataset images using Python PIL library with 40 threads via GNU parallel. This read-heavy workload depends on atime updates for file access tracking.

| Time (seconds) | Patch Status |
|----------------|--------------|
| 542.45         | Baseline     |
| 544.92         | Baseline     |
| 535.03         | Baseline     |
| 542.43         | Baseline     |
| 546.08         | With Patch   |
| 539.22         | With Patch   |
| 555.45         | With Patch   |
| 537.04         | With Patch   |

**Result**: No statistically significant performance difference between patched and unpatched clients.

## Verification

### Verify Patch Installation

1. **Check for patch-specific configuration**:

   ```bash
   grep -i relatime /etc/beegfs/beegfs-client.conf
   ```

2. **Monitor atime updates**:

   ```bash
   # Create test file
   echo "test" > /path/to/beegfs/testfile
   
   # Check initial times
   stat /path/to/beegfs/testfile
   
   # Read the file
   cat /path/to/beegfs/testfile
   
   # Check if atime was updated (should change based on relatime settings)
   stat /path/to/beegfs/testfile
   ```

## Container and Build Environments

The installer automatically detects container and chroot environments and adapts behavior accordingly:

### Supported Environments

- **Docker containers**
- **Podman containers**
- **Chroot environments**
- **Mock build environments**
- **RPM build environments**

### Automatic Detection

When container/chroot environment is detected:

- ✅ Patch is still applied
- ❌ Client rebuild is skipped (not functional in container)
- ❌ Service restart is skipped (systemd not available)
- ℹ️ User is notified about manual steps needed

### Manual Control

Use `--norebuild` to explicitly skip rebuild and service operations:

```bash
# Useful for CI/CD pipelines or custom build processes
sudo ./install.sh --norebuild
```

---

**Note**: This patch modifies BeeGFS client kernel module behavior. Test thoroughly in development environments before production deployment.
