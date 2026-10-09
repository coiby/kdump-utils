# Design Specification: Running `kernel-tests-plans` on GitHub-Hosted Runners

## Context & Objectives

`kdump-utils` end-to-end integration tests were previously adapted to run on GitHub-hosted runners (`ubuntu-latest`) using nested KVM and `tmt` (Test Management Tool). However, CI was only running a single test plan from `tests/` (`lvm2_thinp`), and `kernel-tests-plans` was not being exercised.

The objective is to enable running all 7 test plans defined in `kernel-tests-plans/` (`early`, `local`, `lvm2_thinp`, `nfs_fips`, `nfs`, `nfs_ovs`, and `ssh`) on GitHub-hosted runners using a matrix job in GitHub Actions with freshly built `kdump-utils` RPM packages.

---

## Architecture & Workflows

### 1. Pre-build RPM Job (`build-rpm`)
To avoid compiling and packaging the `kdump-utils` RPM 7 times across the matrix jobs, a dedicated build job runs first:
- **Runner**: `ubuntu-latest`
- **Container**: `quay.io/fedora/fedora:43`
- **Steps**:
  1. Check out repository with `actions/checkout@v6`.
  2. Install RPM build dependencies: `dnf install -y rpm-build make git`.
  3. Run `./tools/build-rpm.sh 43` to produce the RPM under `x86_64/`.
  4. Upload the built RPM using `actions/upload-artifact@v7` under the artifact name `kdump-utils-rpm`.

### 2. Matrix E2E Test Job (`tmt-e2e-tests`)
- **Runner**: `ubuntu-latest`
- **Needs**: `build-rpm`
- **Matrix Strategy**:
  ```yaml
  strategy:
    fail-fast: false
    matrix:
      fedora_version: ["43"]
      plan:
        - early
        - local
        - lvm2_thinp
        - nfs
        - nfs_fips
        - nfs_ovs
        - ssh
  ```
- **Job Timeout**: `90` minutes.
- **Steps**:
  1. Check out repository with `actions/checkout@v6`.
  2. Download the built RPM using `actions/download-artifact@v7` (name: `kdump-utils-rpm`).
  3. Install virtualization stack:
     ```bash
     sudo apt-get update -qq
     sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients libvirt-dev pkg-config genisoimage
     sudo usermod -aG libvirt $USER
     sudo systemctl start libvirtd
     test -e /dev/kvm && echo "KVM OK" || echo "WARNING: /dev/kvm missing"
     sudo virsh list --all
     ```
  4. Install `tmt` and `testcloud`:
     ```bash
     pip install --user tmt testcloud
     echo "$HOME/.local/bin" >> "$GITHUB_PATH"
     tmt --version
     ```
  5. Locate RPM and execute `tmt`:
     ```bash
     RPM_PATH=$(find "$GITHUB_WORKSPACE" -name "kdump-utils-*.rpm" | head -n 1)
     cd kernel-tests-plans && sg libvirt -c "tmt --context install_built_rpm=yes run -a --environment KDUMP_UTILS_RPM=$RPM_PATH provision -h virtual -c system -i fedora:${{ matrix.fedora_version }} plans --name ${{ matrix.plan }}"
     ```
  6. Upload artifacts using `actions/upload-artifact@v7` (with `if: always()`):
     - Name: `tmt-run-${{ matrix.plan }}`
     - Path: `/var/tmp/tmt/run*`

---

## Plan Configurations (`kernel-tests-plans/`)

### 1. Single-Host Plans
- **`early.fmf`**: Discovers `/kdump/config-default-crashkernel`, `/kdump/config-any`, `/kdump/config-earlykdump`. Inherits single `client` guest VM from `main.fmf`.
- **`local.fmf`**: Discovers `/kdump/config-default-crashkernel`, `/kdump/config-any`, `/kdump/crash-sysrq-c`, `/kdump/analyse-crash-cmd/simple_check`. Inherits single `client` guest VM from `main.fmf`.
- **`lvm2_thinp.fmf`**: Promoted from `lvm2_thinp.fmf.new`. Configured with virtual secondary disk for non-packit runners (`disk: [{size: = 40GB}, {size: = 1GB}]`) and `environment: THIN_MP: /dev/vdb` to allow `config-thin` to format the secondary disk and create the thin volume.

### 2. Multi-Host Plans (`ssh`, `nfs`, `nfs_fips`, `nfs_ovs`)
Outside Red Hat internal networks, remote dump tests cannot rely on internal infrastructure (`RESOURCE_URL`). They require multihost provisioning with a secondary `server` VM and restraint synchronization:
- **`ssh.fmf`**:
  - Provision: `client` and `server`.
  - Discovers: `/kdump/config-restraint`, `/kdump/config-default-crashkernel`, `/kdump/config-ssh`, `/kdump/crash-sysrq-c`, `/kdump/copy-ssh`, `/kdump/analyse-crash-cmd/simple_check`.
- **`nfs.fmf`**:
  - Provision: `client` and `server`.
  - Discovers: `/kdump/config-restraint`, `/kdump/config-default-crashkernel`, `/kdump/config-nfs`, `/kdump/crash-sysrq-c`, `/kdump/copy-nfs`, `/kdump/analyse-crash-cmd/simple_check`.
- **`nfs_fips.fmf`**:
  - Provision: `client` and `server`.
  - Discovers: `/kdump/config-restraint`, `/security/crypto/enable_fips`, `/kdump/config-default-crashkernel`, `/kdump/config-nfs`, `/kdump/crash-sysrq-c`, `/kdump/copy-nfs`, `/kdump/analyse-crash-cmd/simple_check`.
- **`nfs_ovs.fmf`**:
  - Provision: `client` and `server`.
  - Discovers: `/kdump/config-restraint`, `/kdump/config-default-crashkernel`, `/kdump/config-ovs`, `/kdump/config-nfs`, `/kdump/crash-sysrq-c`, `/kdump/copy-nfs`, `/kdump/analyse-crash-cmd/simple_check`.

---

## Error Handling & Diagnostics

1. **`fail-fast: false`**: Isolates failures between plans; all test matrix branches run independently.
2. **`exit-first: true`**: Fast failure reporting on the first failing step within any plan.
3. **Artifact Retention**: Full diagnostic logs (including console logs, guest serial logs, beakerlib journals) uploaded unconditionally via `if: always()`.
