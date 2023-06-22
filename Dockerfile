FROM fedora:latest AS basebuild

LABEL maintainer="chuck@milams.net"

RUN dnf -y install bash dos2unix genisoimage grub2-tools-minimal isomd5sum openssh syslinux python3

WORKDIR /create-ks-iso

COPY CONFIG_FILE /create-ks-iso/
COPY create-ks-iso.sh /create-ks-iso/

RUN dos2unix create-ks-iso.sh \
    && dos2unix CONFIG_FILE \
    && chmod +x create-ks-iso.sh

FROM basebuild
COPY --from=basebuild /create-ks-iso/ /create-ks-iso/
ENTRYPOINT ["bash", "-c", "/create-ks-iso/create-ks-iso.sh"]
