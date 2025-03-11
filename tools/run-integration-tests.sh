#!/bin/bash

set -ex

[[ -d ${0%/*} ]] && cd "${0%/*}"/../

for _opt in "$@"; do
	case "$_opt" in
	--fedora_version=*)
		fedora_version=${_opt#*=}
		;;
	--mirror=*)
		mirror=${_opt#*=}
		;;
	--deployment_mode=*)
		deployment_mode=${_opt#*=}
		;;
	--build_rpm=*)
		build_rpm=${_opt#*=}
		;;
	*)
		"Ignore unknown parameter $_opt"
		;;
	esac
done

build_local_rpm() {
	dist_abbr=.fc$fedora_version

	VERSION=$(rpmspec -q --queryformat "%{VERSION}" kdump-utils.spec)
	SRC_ARCHIVE=kdump-utils-$VERSION.tar.gz
	if ! git archive --format=tar.gz -o "$SRC_ARCHIVE" --prefix="kdump-utils-$VERSION/" HEAD; then
		echo "Failed to create kdump-utils source archive"
		exit 1
	fi

	if ! rpmbuild -ba -D "dist $dist_abbr" -D "_sourcedir $(pwd)" -D "_builddir $(pwd)" -D "_srcrpmdir $(pwd)" -D "_rpmdir $(pwd)" kdump-utils.spec; then
		echo "Failed to build kdump-utils rpm"
		exit 1
	fi

	arch=$(uname -m)
	rpm_name=$(rpmspec -D "dist $dist_abbr" -q --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' kdump-utils.spec)
	rpm_path="$(pwd)/${arch}/${rpm_name}.rpm"
	if [[ ! -f $rpm_path ]]; then
		echo "Failed to find built kdump-utils rpm ($rpm_path doesn't eixst)"
		return 1
	fi
	# cp the built rpm to tests rootdir so tmt will copy it to test env automatically
	cp "$rpm_path" ./
}

if [[  $build_rpm == yes ]]; then
	if build_local_rpm; then
		KDUMP_UTILS_RPM=$(basename "$rpm_path")
	fi
fi

[[ -z $mirror ]] && mirror=https://mirrors.tuna.tsinghua.edu.cn/fedora

[[ -z $mirror ]] && [[ $fedora_version == rawhide ]] && mirror=https://mirrors.sjtug.sjtu.edu.cn/fedora/linux

[[ -z $deployment_mode ]] && deployment_mode=package

test_image=/var/tmp/tmt/testcloud/images/
if [[ $deployment_mode == image ]]; then
	test_image+=Fedora-${fedora_version}-image-mode.qcow2
else
	test_image+=Fedora-${fedora_version}.qcow2
fi

if [[ ! -e $test_image ]]; then
	test_image=fedora:"$fedora_version"
fi

cd tests && tmt --context distro="fedora-${fedora_version}" --context deployment_mode="$deployment_mode" run --environment COPR_REPO_URL="$COPR_REPO_URL" --environment CUSTOM_MIRROR="$mirror" --environment KDUMP_UTILS_RPM="$KDUMP_UTILS_RPM" -a provision -h virtual -i "$test_image"
