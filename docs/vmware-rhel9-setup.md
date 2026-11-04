# Red Hat Enterprise Linux 9 Setup Guide on VMware Workstation

This guide walks you through setting up a dedicated **RHEL 9 Virtual Machine** in VMware Workstation to run the 14-node AI Spine-Leaf Fabric Digital Twin.

---

## 1. System Inventory & Hardware Sizing

Your host system has been scanned:
- **VMware Workstation:** Installed (`C:\Program Files\VMware\VMware Workstation`)
- **RHEL 9 ISO:** Detected at `C:\Users\Admin\Downloads\rhel-9.8-x86_64-dvd.iso` (RHEL 9.8 64-bit)
- **Host Specs:** 11th Gen Intel i5 (4 Cores / 8 Threads), 16 GB Total RAM, 53+ GB free disk space.

### Recommended VM Sizing:
| Parameter | Recommended Setting | Rationale |
| :--- | :--- | :--- |
| **Guest OS** | Linux -> Red Hat Enterprise Linux 9 64-bit | Enables RHEL kernel optimization |
| **vCPU** | **4 vCPUs** (1 Socket, 4 Cores) | Leaves 4 threads for Windows host |
| **Virtualization Engine** | Check **"Virtualize Intel VT-x/EPT or AMD-V/RVI"** | Enables nested virtualization for containers |
| **RAM** | **8192 MB (8 GB)** | Optimal for 14 containers; leaves 8 GB for Windows |
| **Disk Size** | **40 GB** (Split or Single, Thin-provisioned) | Initially consumes only ~6 GB on disk |
| **Network Adapter** | **NAT** | Out-of-the-box Internet access for package downloads |

---

## 2. Step-by-Step VMware VM Creation

1. **Launch VMware Workstation** from the Start Menu.
2. Click **File -> New Virtual Machine** (or press `Ctrl+N`).
3. Select **Typical (recommended)** and click **Next**.
4. Choose **Installer disc image file (iso)**:
   - Click **Browse...** and select `C:\Users\Admin\Downloads\rhel-9.8-x86_64-dvd.iso`.
   - Click **Next**.
5. **Easy Install Information** (if prompted by VMware):
   - Full Name: `DC Engineer`
   - User Name: `engineer`
   - Password: `<your-secure-password>`
   - Click **Next**.
6. **Name the Virtual Machine**:
   - Virtual Machine Name: `rhel9-clos-lab`
   - Location: `C:\Users\Admin\Documents\Virtual Machines\rhel9-clos-lab` (or default).
   - Click **Next**.
7. **Specify Disk Capacity**:
   - Maximum disk size (GB): `40.0`
   - Select **Split virtual disk into multiple files** (or single file).
   - Click **Next**.
8. **Customize Hardware** (Crucial Step):
   - Click **Customize Hardware...**
   - **Memory:** Set slider to **8192 MB** (8 GB).
   - **Processors:** Set **Number of cores per processor** to `4`.
   - **Virtualization engine:** Under the Processor settings, check **"Virtualize Intel VT-x/EPT or AMD-V/RVI"**.
   - **Network Adapter:** Verify it is set to **NAT**.
   - Click **Close**, then click **Finish**.

---

## 3. RHEL 9 Operating System Installation

When the VM powers on:
1. Select **Install Red Hat Enterprise Linux 9.8** using the arrow keys and press `Enter`.
2. Select your Language (`English`) and click **Continue**.
3. **Installation Summary**:
   - **Installation Destination:** Click it, ensure the 40 GB VMware virtual disk is checked with "Automatic" storage configuration, then click **Done**.
   - **Software Selection:** Choose **Server with GUI** (or **Minimal Install** if you prefer CLI only).
   - **Root Password / User Creation:** Set the root password and create your administrative user (check "Make this user administrator").
4. Click **Begin Installation**.
5. Once completed, click **Reboot System**.

---

## 4. Transfer the Repository to the VM

You have two simple options:

### Option A: Using VMware Shared Folders (Recommended)
1. In VMware Workstation window, go to **VM -> Settings -> Options tab -> Shared Folders**.
2. Select **Always enabled**, click **Add...**, and select `C:\Users\Admin\Desktop\projectmax\clos-lab-ai`.
3. In RHEL terminal, your repo will appear at `/mnt/hgfs/clos-lab-ai`.

### Option B: Direct Copy via SSH / Git
Inside the RHEL terminal:
```bash
# Obtain the IP of the RHEL VM
ip addr show ens160
```
From Windows PowerShell:
```powershell
# Copy the workspace folder to the VM via scp:
scp -r "C:\Users\Admin\Desktop\projectmax\clos-lab-ai" engineer@<RHEL_IP>:~/clos-lab-ai
```

---

## 5. One-Command RHEL Bootstrap

Inside the RHEL 9 VM terminal:

```bash
cd ~/clos-lab-ai   # or cd /mnt/hgfs/clos-lab-ai
bash scripts/rhel_bootstrap.sh
```

### What this bootstrap script does:
1. Installs EPEL, development tools, Python 3, Jinja2, and network diagnostics.
2. Configures the official Docker CE repo and starts `docker.service`.
3. Installs `containerlab`.
4. Installs `kernel-modules-extra` and loads `sch_red`, `tcp_dctcp`, and `rdma_rxe`.
5. Adjusts `firewalld` to allow Containerlab veth forwarding.
6. Sets kernel sysctls for ECMP multipath hashing (`net.ipv4.fib_multipath_hash_policy=1`) and IP forwarding.
7. Prints a full diagnostic health check.

---

## 6. Proceed to Stage 2

Once `scripts/rhel_bootstrap.sh` completes with all green checks:
```bash
make up
make status
```
All 14 containers will start up, and we will proceed directly with eBGP underlay verification.
