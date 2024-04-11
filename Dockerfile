FROM amazoncorretto:22

RUN yum install -y procps python3 python3-pip

ENV PIPX_BIN_DIR=/opt/bin/

RUN pip3 install pipx && pipx install crypt4gh && pipx ensurepath

COPY globus-file-handler-cli-1.0.0.jar /opt/