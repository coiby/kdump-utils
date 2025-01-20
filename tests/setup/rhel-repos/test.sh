#!/bin/sh -eux

is_RHEL_or_centos() {
    grep -qs -e 'Red Hat Enterprise Linux' -e 'CentOS Stream' /etc/redhat-release
}

is_RHEL_or_centos || exit 0

if ! ping -c3 download.devel.redhat.com; then
    echo "Warning: make sure beakerlib"
    exit 0
fi

if grep -qs -e 'Red Hat Enterprise Linux' /etc/redhat-release; then
    echo sslverify=0 >> /etc/yum.conf
    for name in BaseOS AppStream CRB; do
            cat << EOF >> /etc/yum.repos.d/rhel.repo
[${name}]
name=${name}
baseurl=http://download.devel.redhat.com/rhel-\$releasever/nightly/RHEL-\$releasever/latest-RHEL-\$releasever/compose/${name}/\$basearch/os/
gpgcheck=0
EOF
    done
fi

# harness repo provides packages like beakerlib, restraint and etc.
if is_RHEL_or_centos; then
    cat << 'EOF' >> /etc/yum.repos.d/beaker-harness.repo
[beaker-harness]
name=beaker-harness
baseurl = http://beaker.engineering.redhat.com/harness/RedHatEnterpriseLinux$releasever/
enabled = 1
gpgcheck = 0
EOF
fi
