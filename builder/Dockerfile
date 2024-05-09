FROM fedora:40

RUN dnf install -y rpm-ostree skopeo just
RUN dnf install -y python3 python3-pip python3-devel

COPY ./requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

RUN dnf install -y git jq