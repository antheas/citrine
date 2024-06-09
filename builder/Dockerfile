FROM quay.io/coreos-assembler/fcos-buildroot:testing-devel as build

RUN mkdir -p /sources; \
    cd /sources; \
    git clone https://github.com/coreos/rpm-ostree rpm-ostree;

WORKDIR /sources/rpm-ostree

RUN git submodule update --init; \
    ./autogen.sh --prefix=/usr --libdir=/usr/lib64 --sysconfdir=/etc

RUN cargo fetch

COPY 0001-skip-multiple-packages-check-to-avoid-32bit-packages.patch /tmp/patch.patch
RUN patch -Np1 < "/tmp/patch.patch"

RUN make

RUN dnf install -y skopeo just git jq selinux-policy-targeted make bubblewrap
RUN dnf install -y python3 python3-pip python3-devel
RUN make install

WORKDIR /workspace

COPY ./requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

ARG UID=1000
ARG GID=1000

RUN groupadd admin -g $GID && \
    useradd admin -u $UID -g admin -ms /bin/bash && \
    passwd -d admin && \
    echo "admin ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/user && \
    chmod 0440 /etc/sudoers.d/user

RUN dnf install -y fedpkg