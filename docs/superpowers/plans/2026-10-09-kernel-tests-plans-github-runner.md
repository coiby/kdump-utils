# Running `kernel-tests-plans` on GitHub-Hosted Runners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable running all 7 integration test plans in `kernel-tests-plans` (`early`, `local`, `lvm2_thinp`, `nfs`, `nfs_fips`, `nfs_ovs`, `ssh`) on GitHub-hosted runners using a matrix job with a freshly built `kdump-utils` RPM.

**Architecture:** A dedicated `build-rpm` job builds the package on `quay.io/fedora/fedora:43` and uploads the RPM artifact. A parallel matrix job `tmt-e2e-tests` downloads the RPM and runs each plan on `ubuntu-latest` using nested KVM and `tmt`. Multi-host plans (`ssh`, `nfs`, `nfs_fips`, `nfs_ovs`) are configured with `client` and `server` VMs plus restraint synchronization.

**Tech Stack:** GitHub Actions, tmt (Test Management Tool), testcloud, libvirt/qemu-kvm, rpmbuild, beakerlib, restraint.

---

### Task 1: Configure Multi-Host Test Plans (`ssh`, `nfs`, `nfs_fips`, `nfs_ovs`)

**Files:**
- Modify: `kernel-tests-plans/ssh.fmf`
- Modify: `kernel-tests-plans/nfs.fmf`
- Modify: `kernel-tests-plans/nfs_fips.fmf`
- Modify: `kernel-tests-plans/nfs_ovs.fmf`
- Remove untracked: `kernel-tests-plans/ssh.fmf_restraint`

- [ ] **Step 1: Update `kernel-tests-plans/ssh.fmf`**

Add `client` and `server` provisioning and `/kdump/config-restraint`:

```yaml
summary: Kdump ssh dumping tests

provision:
   - name: client
   - name: server

discover+:
    test:
     - /kdump/config-restraint
     - /kdump/config-default-crashkernel
     - /kdump/config-ssh
     - /kdump/crash-sysrq-c
     - /kdump/copy-ssh
     - /kdump/analyse-crash-cmd/simple_check
```

- [ ] **Step 2: Update `kernel-tests-plans/nfs.fmf`**

Add `client` and `server` provisioning and `/kdump/config-restraint`:

```yaml
summary: Kdump NFS dumping tests

provision:
   - name: client
   - name: server

discover+:
    test:
     - /kdump/config-restraint
     - /kdump/config-default-crashkernel
     - /kdump/config-nfs
     - /kdump/crash-sysrq-c
     - /kdump/copy-nfs
     - /kdump/analyse-crash-cmd/simple_check
```

- [ ] **Step 3: Update `kernel-tests-plans/nfs_fips.fmf`**

Add `client` and `server` provisioning and `/kdump/config-restraint`:

```yaml
summary: Kdump NFS dumping tests with FIPS enabled

provision:
   - name: client
   - name: server

discover+:
    test:
     - /kdump/config-restraint
     - /security/crypto/enable_fips
     - /kdump/config-default-crashkernel
     - /kdump/config-nfs
     - /kdump/crash-sysrq-c
     - /kdump/copy-nfs
     - /kdump/analyse-crash-cmd/simple_check
```

- [ ] **Step 4: Update `kernel-tests-plans/nfs_ovs.fmf`**

Add `client` and `server` provisioning and `/kdump/config-restraint`:

```yaml
summary: Kdump NFS dumping over OVS bridge tests

provision:
   - name: client
   - name: server

discover+:
    test:
     - /kdump/config-restraint
     - /kdump/config-default-crashkernel
     - /kdump/config-ovs
     - /kdump/config-nfs
     - /kdump/crash-sysrq-c
     - /kdump/copy-nfs
     - /kdump/analyse-crash-cmd/simple_check

adjust:
   - when: distro == fedora-rawhide and initiator == packit
     enabled: false
     because: somehow the config-ovs test just fails on some testing farm AWS machines
```

- [ ] **Step 5: Remove redundant untracked `kernel-tests-plans/ssh.fmf_restraint`**

Run: `rm -f kernel-tests-plans/ssh.fmf_restraint`

- [ ] **Step 6: Validate plan definitions with tmt**

Run: `cd kernel-tests-plans && tmt plan show /ssh && tmt plan show /nfs && tmt plan show /nfs_fips && tmt plan show /nfs_ovs`
Expected: Output shows all 4 plans with `provision` (client, server) and `discover` including `/kdump/config-restraint`.

- [ ] **Step 7: Commit multi-host plan changes**

```bash
git add kernel-tests-plans/ssh.fmf kernel-tests-plans/nfs.fmf kernel-tests-plans/nfs_fips.fmf kernel-tests-plans/nfs_ovs.fmf
git commit -m "tests: configure multi-host plans for virtual runner execution"
```

---

### Task 2: Configure LVM2 Thin Provisioning Plan (`lvm2_thinp.fmf`)

**Files:**
- Create: `kernel-tests-plans/lvm2_thinp.fmf`
- Remove: `kernel-tests-plans/lvm2_thinp.fmf.new`

- [ ] **Step 1: Create `kernel-tests-plans/lvm2_thinp.fmf`**

Create `kernel-tests-plans/lvm2_thinp.fmf` with secondary disk configuration and `THIN_MP`:

```yaml
summary: Kdump LVM2 thin provision tests
discover+:
    test:
     - /kdump/config-default-crashkernel
     - /kdump/config-thin
     - /kdump/crash-sysrq-c
     - /kdump/analyse-crash-cmd/simple_check

provision:
   - name: client
     beaker:
         pool: beaker

     kickstart:
       script: |
           zerombr
           clearpart --all
           reqpart
           part /boot --fstype=ext4 --size=2048
           part / --fstype=xfs --size=4096 --grow
           part /thinp --fstype=xfs --size=10240
       metadata: no_autopart

adjust:
   - when: initiator != packit
     provision:
        name: client
        how: virtual
        connection: system
        hardware:
           disk:
             - size: = 40GB
             - size: = 1GB
     environment+:
        THIN_MP: /dev/vdb
```

- [ ] **Step 2: Remove untracked `kernel-tests-plans/lvm2_thinp.fmf.new`**

Run: `rm -f kernel-tests-plans/lvm2_thinp.fmf.new`

- [ ] **Step 3: Validate `lvm2_thinp` plan with tmt**

Run: `cd kernel-tests-plans && tmt plan show /lvm2_thinp`
Expected: Output shows `/lvm2_thinp` with `config-thin` and disk hardware requirements.

- [ ] **Step 4: Commit `lvm2_thinp` plan**

```bash
git add kernel-tests-plans/lvm2_thinp.fmf
git commit -m "tests: add lvm2_thinp test plan to kernel-tests-plans"
```

---

### Task 3: Update GitHub Actions Workflow (`.github/workflows/main.yml`)

**Files:**
- Modify: `.github/workflows/main.yml`

- [ ] **Step 1: Update `.github/workflows/main.yml` with `build-rpm` and `tmt-e2e-tests` matrix**

Edit `.github/workflows/main.yml`:

```yaml
name: kdump-utils tests

on: [pull_request, workflow_dispatch]

jobs:
  build-rpm:
    runs-on: ubuntu-latest
    container:
      image: quay.io/fedora/fedora:43
    steps:
      - uses: actions/checkout@v6

      - name: Install build dependencies
        run: dnf install -y rpm-build make git sed

      - name: Build kdump-utils RPM
        run: |
          git config --global --add safe.directory "$GITHUB_WORKSPACE"
          ./tools/build-rpm.sh 43

      - name: Upload built RPM
        uses: actions/upload-artifact@v7
        with:
          name: kdump-utils-rpm
          path: x86_64/*.rpm
          if-no-files-found: error

  tmt-e2e-tests:
    needs: [build-rpm]
    runs-on: ubuntu-latest

    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}-${{ matrix.fedora_version }}-${{ matrix.plan }}
      cancel-in-progress: true
    strategy:
      matrix:
        fedora_version:
          - "43"
        plan:
          - early
          - local
          - lvm2_thinp
          - nfs
          - nfs_fips
          - nfs_ovs
          - ssh
      fail-fast: false

    timeout-minutes: 90
    steps:
      - uses: actions/checkout@v6

      - name: Download built RPM
        uses: actions/download-artifact@v7
        with:
          name: kdump-utils-rpm
          path: built-rpm

      - name: Install libvirt
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients libvirt-dev pkg-config genisoimage
          sudo usermod -aG libvirt $USER
          sudo systemctl start libvirtd
          # verify KVM is available
          test -e /dev/kvm && echo "KVM OK" || echo "WARNING: /dev/kvm missing"
          sudo virsh list --all

      - name: Install tmt + testcloud
        run: |
          pip install --user tmt testcloud
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
          tmt --version

      - name: Run e2e test (${{ matrix.plan }})
        run: |
          RPM_PATH=$(find "$GITHUB_WORKSPACE/built-rpm" -name "kdump-utils-*.rpm" | head -n 1)
          echo "Using built RPM: $RPM_PATH"
          test -f "$RPM_PATH" || { echo "RPM not found"; exit 1; }
          cd kernel-tests-plans && sg libvirt -c "tmt --context install_built_rpm=yes run -a --environment KDUMP_UTILS_RPM=\"$RPM_PATH\" provision -h virtual -c system -i fedora:${{ matrix.fedora_version }} plans --name ${{ matrix.plan }}"

      - name: Upload tmt artifacts
        uses: actions/upload-artifact@v7
        if: always()
        with:
          name: tmt-run-${{ matrix.plan }}
          path: /var/tmp/tmt/run*
          if-no-files-found: ignore
```

- [ ] **Step 2: Verify YAML syntax of `.github/workflows/main.yml`**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/main.yml'))"`
Expected: No syntax errors.

- [ ] **Step 3: Commit workflow changes**

```bash
git add .github/workflows/main.yml
git commit -m "ci: run kernel-tests-plans matrix on GitHub-hosted runner with built RPM"
```

---

### Task 4: End-to-End Local Verification of All Plans

**Files:**
- Verify: `kernel-tests-plans/`

- [ ] **Step 1: Check listing of all plans in `kernel-tests-plans`**

Run: `cd kernel-tests-plans && tmt plan ls`
Expected output:
```
/early
/local
/lvm2_thinp
/nfs
/nfs_fips
/nfs_ovs
/ssh
```

- [ ] **Step 2: Inspect plan details with `--context install_built_rpm=yes`**

Run: `cd kernel-tests-plans && for p in early local lvm2_thinp nfs nfs_fips nfs_ovs ssh; do echo "=== $p ===" && tmt --context install_built_rpm=yes plan show "/$p" | grep -E "(summary|Install built RPM|config-restraint|how virtual)"; done`
Expected:
All 7 plans show summary, `Install built RPM` task, and multi-host plans show `config-restraint`.

- [ ] **Step 3: Check git status to ensure working directory is clean**

Run: `git status`
Expected: Working tree clean (or untracked scratch files ignored).
