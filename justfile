# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run via Pungi in a Koji runroot.

# Set a default for some recipes
distro := "ametrine"
default_variant := "ametrine"
max_layers := "50"
build_timestamp := "1715354581"

# Comps-sync, but without pulling latest
sync:
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo ${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in

# Sync the manifests with the content of the comps groups
comps-sync:
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo ${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in

# Check if the manifests are in sync with the content of the comps groups
comps-sync-check:
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo ${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py fedora-comps/comps-f${version}.xml.in

# Output the processed manifest for a given variant (defaults to Silverblue)
manifest variant=default_variant:
    #!/bin/bash
    set -euo pipefail
    rpm-ostree compose tree --print-only --repo=repo {{variant}}.yaml

# Perform dependency resolution for a given variant (defaults to Silverblue)
compose-dry-run variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi

    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose tree --unified-core --repo=repo --dry-run {{variant}}.yaml

# Alias/shortcut for compose-image command
compose variant=default_variant: (compose-image variant)

# Compose an Ostree Native Container OCI image
compose-image variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "citrine")
            variant_pretty="Citrine"
            ;;
        "ametrine")
            variant_pretty="Ametrine"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    mkdir -p repo cache
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

    # Find the name of the next ver based on what has been built
    version="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    do=true
    i=0
    out_archive=""
    while $do || [[ -f $out_archive ]]; do
        do=false
        buildid="$(date '+%Y%m%d').${i}"
        out_fn="${variant}.${version}.${buildid}"
        out_archive="${out_fn}.ociarchive"
        i=$((i + 1))
    done

    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid
    echo "--- Composing ${variant_pretty} ${version}.${buildid} to ${out_archive}"

    # To debug with gdb, use: gdb --args ...
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    # Install the packages
    # These three commands are a destructured tree command
    # but have overhead
    # ${CMD} compose install \
    #     --unified-core --cachedir=cache --repo=repo \
    #     ${variant}.yaml ./sysroot
    # ${CMD} compose postprocess \
    #     --unified-core \
    #     ./sysroot/rootfs ${variant}.yaml
    # ${CMD} compose commit \
    #     --repo=./repo --unified-core \
    #     ${variant}.yaml ./sysroot/rootfs
    # Just tree command
    # Export source date epoch to improve determinism
    export SOURCE_DATE_EPOCH={{build_timestamp}}
    ${CMD} compose tree \
        --unified-core --cachedir=cache --repo=repo \
        ${variant}.yaml \
        --write-commitid-to="interim.${variant}.commitid.txt" \
        --write-composejson-to="interim.${variant}.compose.json"

    # Reference previous manifest to avoid layer shifting
    CE_ARGS=""
    if [[ -f "interim.${variant}.manifest.json" ]]; then
        CE_ARGS+="--previous-build-manifest interim.${variant}.manifest.json"
    fi

    # Create OCI archive
    commitid=$(cat interim.${variant}.commitid.txt)
    ${CMD} compose container-encapsulate \
        --repo repo ${commitid} \
        --max-layers {{max_layers}} ${CE_ARGS} \
        oci-archive:${out_archive}
    
    # Save data for transparency
    skopeo inspect --raw oci-archive:${out_archive} > interim.${variant}.manifest.json
    mkdir -p manifests
    cp interim.${variant}.manifest.json manifests/${out_fn}.manifest.json
    cp interim.${variant}.commitid.txt manifests/${out_fn}.commitid.txt
    cp interim.${variant}.compose.json manifests/${out_fn}.compose.json
    echo "Wrote image manifest to manifests/${out_fn}.manifest.json"

    rm -f ${variant}.ociarchive
    ln -s ${out_fn} ${variant}.ociarchive
    
    # This is a combined command and cant reuse metadata etc, is inflexible
    # ${CMD} compose image ${ARGS} \
    #     "${variant}.yaml" \
    #     "${variant}.ociarchive"
    #     #  --label="quay.expires-after=4w" \

# Clean up everything
clean-all:
    just clean-repo
    just clean-cache

# Only clean the ostree repo
clean-repo:
    sudo rm -rf ./repo

# Only clean the package and repo caches
clean-cache:
    sudo rm -rf ./cache

# Build an ISO
lorax variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    rm -rf iso
    # Do not create the iso directory or lorax will fail
    mkdir -p tmp cache/lorax

    variant={{variant}}
    case "${variant}" in
        "citrine")
            variant_pretty="Citrine"
            ;;
        "ametrine")
            variant_pretty="Ametrine"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    if [[ ! -d fedora-lorax-templates ]]; then
        git clone https://pagure.io/fedora-lorax-templates.git
    else
        pushd fedora-lorax-templates > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    version_number="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version_pretty="Rawhide"
        version="rawhide"
    else
        version_pretty="${version_number}"
        version="${version_number}"
    fi
    source_url="https://kojipkgs.fedoraproject.org/compose/${version}/latest-Fedora-${version_pretty}/compose/Everything/x86_64/os/"
    volid="Fedora-${volid_sub}-x86_64-${version_pretty}"

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    # Stick to the latest stable runtime available here
    # Only include a subset of Flatpaks here
    # Exhaustive list in https://pagure.io/pungi-fedora/blob/main/f/fedora.conf
    # flatpak_remote_refs="runtime/org.fedoraproject.Platform/x86_64/f39"
    # flatpak_apps=(
    #     "app/org.gnome.Calculator/x86_64/stable"
    #     "app/org.gnome.Calendar/x86_64/stable"
    #     "app/org.gnome.Extensions/x86_64/stable"
    #     "app/org.gnome.TextEditor/x86_64/stable"
    #     "app/org.gnome.clocks/x86_64/stable"
    #     "app/org.gnome.eog/x86_64/stable"
    # )
    # for ref in ${flatpak_refs[@]}; do
    #     flatpak_remote_refs+=" ${ref}"
    # done
    # FLATPAK_ARGS=""
    # FLATPAK_ARGS+=" --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-flatpaks.tmpl"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_name=fedora"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_url=oci+https://registry.fedoraproject.org"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_refs=${flatpak_remote_refs}"

    pwd="$(pwd)"

    lorax \
        --product=Fedora \
        --version=${version_pretty} \
        --release=${buildid} \
        --source="${source_url}" \
        --variant="${variant_pretty}" \
        --nomacboot \
        --isfinal \
        --buildarch=x86_64 \
        --volid="${volid}" \
        --logfile=${pwd}/logs/lorax.log \
        --tmp=${pwd}/tmp \
        --cachedir=cache/lorax \
        --rootfs-size=8 \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-configure-repo.tmpl \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-repo.tmpl \
        --add-template-var=ostree_install_repo=file://${pwd}/repo \
        --add-template-var=ostree_update_repo=file://${pwd}/repo \
        --add-template-var=ostree_osname=fedora \
        --add-template-var=ostree_oskey=fedora-${version_number}-primary \
        --add-template-var=ostree_contenturl=mirrorlist=https://ostree.fedoraproject.org/mirrorlist \
        --add-template-var=ostree_install_ref=fedora/${version}/x86_64/${variant} \
        --add-template-var=ostree_update_ref=fedora/${version}/x86_64/${variant} \
        ${pwd}/iso/linux

# Upload the containers to a registry (Quay.io)
upload-container variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    variant={{variant}}
    case "${variant}" in
        "citrine")
            variant_pretty="Citrine"
            ;;
        "ametrine")
            variant_pretty="Ametrine"
            ;;
        "*")
            echo "Unknown variant"
            exit 1
            ;;
    esac

    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi
    if [[ "${CI}" != "true" ]]; then
        echo "Skipping artifact archiving: Not in CI"
        exit 0
    fi

    version=""
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version="rawhide"
    else
        version="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    fi

    image="quay.io/fedora-ostree-desktops/${variant}"
    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    git_commit=""
    if [[ -n "${CI_COMMIT_SHORT_SHA}" ]]; then
        git_commit="${CI_COMMIT_SHORT_SHA}"
    else
        git_commit="$(git rev-parse --short HEAD)"
    fi

    # skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" quay.io
    # # Copy fully versioned tag (major version, build date/id, git commit)
    # skopeo copy --retry-times 3 "oci-archive:${variant}.ociarchive" "docker://${image}:${version}.${buildid}.${git_commit}"
    # # Update "un-versioned" tag (only major version)
    # skopeo copy --retry-times 3 "docker://${image}:${version}.${buildid}.${git_commit}" "docker://${image}:${version}"
