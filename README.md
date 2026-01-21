# Building QEMU with the Wasm TCG backend support

Patch is maintained in https://github.com/ktock/qemu-wasm/pull/33

Assuming this repository and [a patch for the Wasm TCG backend support](https://github.com/ktock/qemu-wasm/pull/33) are cloned locally.
Set the current directory to the root directory of this repository.
Set `QEMU_REPO` environment variable to the path of the locally cloned QEMU repository.

## Compiling QEMU

The QEMU repository provides a Dockerfile `emsdk-wasm-cross.docker` which contains dependencies and toolchains to compile QEMU for wasm64.
This contains the following prerequisites:

- Emscripten SDK (emsdk) v4.0.23
- Libraries cross-compiled with Emscripten (please see also the `emsdk-wasm-cross.docker` Dockerfile for build steps)
  - GLib v2.84.0
  - zlib v1.3.1
  - libffi v3.5.2
  - Pixman v0.44.2

The following commands build this container with the name `build-qemu-wasm64-base`.

```
$ docker build -t build-qemu-wasm64-base - < ${QEMU_REPO}/tests/docker/dockerfiles/emsdk-wasm-cross.docker
```

Based on the container built above, the following commands add some demo guest images and start a shell in the container.

```
$ docker build -t build-qemu-wasm64 --build-arg QEMU_BASE_IMAGE=build-qemu-wasm64-base .
$ docker run --rm --init -d --name build-qemu-wasm64 -v ${QEMU_REPO}:/qemu/:ro build-qemu-wasm64
$ docker exec -it build-qemu-wasm64 /bin/bash
```

QEMU can be compiled in either of the following options, depending on the compatibility requirements of the target engine.

### Option 1: Compiling QEMU for wasm64

QEMU can be compiled to a wasm64 binary.
Note that some engines, including Safari, don't support wasm64 as of now.
The adoption status of wasm64 can be seen at https://webassembly.org/features/ .

QEMU can be compiled using Emscripten's emconfigure and emmake, which automatically set environment variables such as CC for targeting Emscripten.
QEMU's configure script supports `--cpu=wasm64` flag to compile QEMU to wasm64.

Run the following in the `build-qemu-wasm64` container.

```
emconfigure /qemu/configure --cpu=wasm64 --static --disable-tools \
                            --target-list=x86_64-softmmu
emmake make -j$(nproc)
```

This process generates the following files:

- qemu-system-x86_64.js
- qemu-system-x86_64.wasm

### Option 2: Compiling QEMU for wasm64 with compatibility for wasm32 engines

This section shows steps to compile QEMU for wasm64 while still allowing it to run on wasm32 engines, using Emscripten's [`-sMEMORY64=2`](https://emscripten.org/docs/tools_reference/settings_reference.html#memory64).
This flag still enables 64bit pointers in the C code and Emscripten lowers the output to wasm32 with a memory limit of 4GB, which allows QEMU to run on wasm32 engines.

QEMU can be compiled using Emscripten's emconfigure and emmake.
QEMU's configure script supports `--cpu=wasm64` and `--enable-wasm64-32bit-address-limit` flags to enable the `-sMEMORY64=2` feature.

Run the following in the `build-qemu-wasm64` container.

```
emconfigure /qemu/configure --cpu=wasm64 --enable-wasm64-32bit-address-limit --static --disable-tools \
                            --target-list=x86_64-softmmu
emmake make -j$(nproc)
```

This process generates the following files:

- qemu-system-x86_64.js
- qemu-system-x86_64.wasm

## Bundling guest assets

Sample guest images (under `/images/` dir in the container) can be packaged using Emscripten's file_packager.py tool.
The following command packages them, allowing QEMU to access them through Emscripten's virtual filesystem:

The following needs to run inside the build environment container.

```
mkdir pack
cp /images/kernel.img pack/
cp /images/rootfs.bin pack/
cp -r /qemu/pc-bios/* pack/
/emsdk/upstream/emscripten/tools/file_packager.py qemu-system-x86_64.data --preload pack --export-es6 > load.js
```

This process generates the following files:

- qemu-system-x86_64.data
- load.js

## Run the Wasm-compiled QEMU using Node.js

You can run the Wasm-compiled QEMU on Node.js.
This allows quick testing of the Wasm-compiled QEMU within the terminal, without launching an HTTP server.

There is a helper JS script `scripts/run-emscripten.mjs` in the QEMU repository.
It runs the Wasm-compiled QEMU with loading the assets specified with the `--preload` flag.

In the `build-qemu-wasm64` container, Node.js 24 is already installed.
Run the following in the `/build` directory to start QEMU on Node.js.

```
node ./scripts/run-emscripten.mjs --preload ./load.js ./qemu-system-x86_64.js -- \
     -nographic -m 512M \
     -L pack/ \
     -drive if=virtio,format=raw,file=pack/rootfs.bin \
     -kernel pack/kernel.img \
     -append "earlyprintk=ttyS0 console=ttyS0 root=/dev/vda loglevel=7"
```

Node.js 24 or newer is needed to run wasm64 binaries. Also note that QEMU's "quit" monitor command doesn't work as of now because of the Emscripten's [atexit issue](https://github.com/emscripten-core/emscripten/issues/26040). Send SIGINT or SIGTERM to the node process to exit QEMU.

## Serve QEMU to the browser

You can run the Wasm-compiled QEMU inside browser.
This repository relies on [xterm-pty](https://github.com/mame/xterm-pty) library for the terminal UI on the browser.

Firstly, you need to recompile the QEMU binary to link with the xterm-pty library.
xterm-pty dependencies are already installed in the `build-qemu-wasm64` container and you can pass the necessary compilation flags to Emscripten using `EMCC_CFLAGS=${XTERM_PTY_CFLAGS}`.

```
EMCC_CFLAGS=${XTERM_PTY_CFLAGS} emconfigure /qemu/configure --cpu=wasm64 --enable-wasm64-32bit-address-limit --static --disable-tools --target-list=x86_64-softmmu
EMCC_CFLAGS=${XTERM_PTY_CFLAGS} emmake make -j$(nproc)
```

This process generates the following files again:

- qemu-system-x86_64.js
- qemu-system-x86_64.wasm

To serve those files to the browser at localhost, run the following commands outside the build environment container.

```
mkdir -p /tmp/test/htdocs/
docker cp build-qemu-wasm64:/build/qemu-system-x86_64.js /tmp/test/htdocs/out.js
for f in qemu-system-x86_64.wasm qemu-system-x86_64.data load.js ; do
  docker cp build-qemu-wasm64:/build/${f} /tmp/test/htdocs/
done
cp ./samples/{index.html,module.js} /tmp/test/htdocs/
cp ./samples/cc.conf /tmp/test/
docker run --rm -d -p 127.0.0.1:8888:80 \
       -v "/tmp/test/htdocs:/usr/local/apache2/htdocs/:ro" \
       -v "/tmp/test/cc.conf:/usr/local/apache2/conf/extra/cc.conf:ro" \
       --entrypoint=/bin/sh httpd -c 'echo "Include conf/extra/cc.conf" >> /usr/local/apache2/conf/httpd.conf && httpd-foreground'
```

This command example also serves the sample HTML file ([`./samples/index.html`](./samples/index.html)) which implements a terminal UI using xterm-pty.
Flags and arguments are passed to QEMU via Emscripten's Module object ([`./samples/module.js`](./samples/module.js)).

Then you can start QEMU by accessing `localhost:8888` from the browser.

> NOTE: A httpd configuration file (`cc.conf`) is used for setting COOP and COEP headers to enable SharedArrayBuffer. This is needed by Emscripten's pthreads support. For more details, please refer to the doc: https://emscripten.org/docs/porting/pthreads.html
