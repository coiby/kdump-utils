#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

download_copr_repo() {
    # Maximum wait time in seconds
    MAX_WAIT=120
    # Retry interval in seconds
    RETRY_INTERVAL=5
    # Track elapsed time
    ELAPSED_TIME=0

    DESTINATION="/etc/yum.repos.d/$(basename "$COPR_REPO_URL")"

    while [ "$ELAPSED_TIME" -lt "$MAX_WAIT" ]; do
        echo "Attempting to download COPR repo..."

        # Try to download the repo file
        if curl -fSL "$COPR_REPO_URL" -o "$DESTINATION"; then
            echo "Successfully downloaded COPR repo to $DESTINATION"
            return 0
        else
            echo "Repo not available. Retrying in $RETRY_INTERVAL seconds..."
            sleep "$RETRY_INTERVAL"
            ELAPSED_TIME=$((ELAPSED_TIME + RETRY_INTERVAL))
        fi
    done

    echo "Failed to download COPR repo after $MAX_WAIT seconds. Exiting."
    return 1
}

rlJournalStart
    rlPhaseStartTest
    if [[ -n "$COPR_REPO_URL" ]]; then
        rlRun "download_copr_repo" 0 "Enable COPR project"
    fi

    if [[ -n "$KDUMP_UTILS_RPM" ]]; then
        if test -f /run/ostree-booted; then
            if [[ -n "$COPR_REPO_URL" ]]; then
                rlRun "rpm-ostree install -A --allow-inactive --idempotent dnf-plugins-core -y" 0 "Install dnf-plugins-core"
                rlRun "dnf download $KDUMP_UTILS_RPM" 0 "Download kdump-utils"
            fi
            rlRun "rpm-ostree override replace $KDUMP_UTILS_RPM" 0 "Install kdump-utils"
            rlRun "rpm-ostree apply-live --allow-replacement" 0 "Apply overrides live"
        fi
    fi
    rlPhaseEnd

rlJournalEnd
