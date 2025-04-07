ARG QEMU_BASE_IMAGE=build-qemu-base

FROM ubuntu:22.04 AS rootfs-dev
ARG BUSYBOX_VERSION=1.36.1
RUN apt-get update && apt-get install -y gcc-x86-64-linux-gnu linux-libc-dev-amd64-cross git make gcc bzip2 wget
WORKDIR /work
RUN wget https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
RUN bzip2 -d busybox-${BUSYBOX_VERSION}.tar.bz2
RUN tar xf busybox-${BUSYBOX_VERSION}.tar
WORKDIR /work/busybox-${BUSYBOX_VERSION}
RUN make CROSS_COMPILE=x86_64-linux-gnu- LDFLAGS=--static defconfig
RUN make CROSS_COMPILE=x86_64-linux-gnu- LDFLAGS=--static -j$(nproc)
RUN mkdir -p /rootfs/bin && mv busybox /rootfs/bin/busybox
RUN make LDFLAGS=--static defconfig
RUN make LDFLAGS=--static -j$(nproc)
RUN for i in $(./busybox --list) ; do ln -s busybox /rootfs/bin/$i ; done
RUN mkdir -p /rootfs/usr/share/udhcpc/ && cp ./examples/udhcp/simple.script /rootfs/usr/share/udhcpc/default.script
RUN mkdir -p /rootfs/proc /rootfs/sys /rootfs/mnt /rootfs/run /rootfs/tmp /rootfs/dev /rootfs/var /rootfs/etc && mknod /rootfs/dev/null c 1 3 && chmod 666 /rootfs/dev/null
COPY ./src/rcS /rootfs/etc/init.d/
RUN chmod 700 /rootfs/etc/init.d/rcS
RUN dd if=/dev/zero of=rootfs.bin bs=4M count=1
RUN mke2fs -d /rootfs rootfs.bin
RUN mkdir /out/ && mv rootfs.bin /out/

FROM ubuntu:24.04 AS kernel-dev
RUN apt-get update && apt-get install -y gcc-x86-64-linux-gnu linux-libc-dev-amd64-cross git make gperf flex bison bc libelf-dev
RUN apt-get install -y xz-utils
RUN mkdir /work-buildlinux
WORKDIR /work-buildlinux
RUN git clone -b v6.1 --depth 1 https://github.com/torvalds/linux
WORKDIR /work-buildlinux/linux
COPY ./src/linux_x86_64_config ./.config
RUN make ARCH=x86 CROSS_COMPILE=x86_64-linux-gnu- -j$(nproc) all && \
    mkdir /out && \
    mv /work-buildlinux/linux/arch/x86/boot/bzImage /out/kernel.img && \
    make clean

FROM ${QEMU_BASE_IMAGE}
WORKDIR /builddeps/
ENV EMCC_CFLAGS="--js-library=/builddeps/node_modules/xterm-pty/emscripten-pty.js"
RUN npm i xterm-pty@v0.10.1
WORKDIR /build/

COPY --from=rootfs-dev /out/rootfs.bin /images/
COPY --from=kernel-dev /out/kernel.img /images/

CMD ["sleep", "infinity"]
