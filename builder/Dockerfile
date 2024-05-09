FROM fedora:40

RUN dnf install -y rpm-ostree skopeo just git jq selinux-policy-targeted
RUN dnf install -y python3 python3-pip python3-devel

COPY ./requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

ARG UID=1000
ARG GID=1000

RUN groupadd admin -g $GID && \
    useradd admin -u $UID -g admin -ms /bin/bash && \
    passwd -d admin && \
    echo "admin ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/user && \
    chmod 0440 /etc/sudoers.d/user