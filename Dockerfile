FROM almalinux:latest

WORKDIR /create-ks-iso

COPY CONFIG_FILE /create-ks-iso/
COPY create-ks-iso.sh /create-ks-iso/

RUN dnf -y install bash genisoimage git isomd5sum openssh syslinux python3 \
    --mount=type=bind,source=/result,target=/create-ks-iso/result,rw \
    --mount=type=bind,source=/isosrc,target=/create-ks-iso/isosrc,ro \
    ["/bin/bash", "-c", "./create-ks-iso.sh"]


