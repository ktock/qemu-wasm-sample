# Building QEMU with emscripten with Wasm backend patch

Patch is maintained in https://github.com/ktock/qemu-wasm/pull/21

Assuming this repository and [Wasm backend patch](https://github.com/ktock/qemu-wasm/pull/21) are cloned locally.
Set the current directory to the root directory of this repository.

## Prepare build environemnt

Build and start the build environment container.
This contains the following prerequisites.

- emscripten SDK (emsdk) v3.1.50
- Libraries cross-compiled with emscripten (refer to emsdk-wasm32-cross.docker for build steps)
  - GLib 2.84.0
  - zlib 1.3.1
  - libffi 3.4.7
  - Pixman 0.44.2

This container also contains xterm-pty which is an on-browser terminal emulator integrated with emscripten.

Set `QEMU_REPO` envvar to the path of the local QEMU repository with the Wasm backend patch.
Run the following command to build the container.

```
docker build --progress=plain -t build-qemu-base - < ${QEMU_REPO}/tests/docker/dockerfiles/emsdk-wasm32-cross.docker
docker build --progress=plain -t build-qemu .
docker run --rm --init -d --name build-qemu -v ${QEMU_REPO}:/qemu/:ro build-qemu
```

## Build QEMU using emscripten

This section need to run inside the build environment container.
`docker exec` command can start the shell in the container.

```
docker exec -it build-qemu /bin/bash
```

QEMU can be compiled using Emscripten's emconfigure and emmake, which automatically set environment variables such as CC for targeting Emscripten.

```
emconfigure /qemu/configure --static --disable-tools --target-list=x86_64-softmmu
emmake make -j$(nproc)
```

> NOTE: add --enable-tcg-interpreter to enable TCI mode

This process generates the following files:

- qemu-system-x86_64.js
- qemu-system-x86_64.wasm
- qemu-system-x86_64.worker.js

Sample guest images (under `/images/` dir in the container) can be packaged using Emscripten's file_packager.py tool.
The following command packages them, allowing QEMU to access them through Emscripten's virtual filesystem:

```
mkdir pack
cp /images/kernel.img pack/
cp /images/rootfs.bin pack/
cp -r /qemu/pc-bios/* pack/
/emsdk/upstream/emscripten/tools/file_packager.py qemu-system-x86_64.data --preload pack > load.js
```

This process generates the following files:

- qemu-system-x86_64.data
- load.js

## Serve QEMU to the browser

This section needs to run outside of the build environment container.

Serve these generated files on localhost with a sample HTML file that implements a terminal UI.
Emscripten allows passing arguments to the QEMU command via the Module object in JavaScript (e.g. [`./samples/module.js`](./samples/module.js)).

> NOTE: Additional configuration for httpd (`cc.conf`) is needed for setting COOP and COEP headers to enable SharedArrayBuffer. This is needed by emscripten's pthreads support. For more details, please refer to the doc: https://emscripten.org/docs/porting/pthreads.html

```
mkdir -p /tmp/test/htdocs/
docker cp build-qemu:/build/qemu-system-x86_64.js /tmp/test/htdocs/out.js
for f in qemu-system-x86_64.wasm qemu-system-x86_64.worker.js qemu-system-x86_64.data load.js ; do
  docker cp build-qemu:/build/${f} /tmp/test/htdocs/
done
cp ./samples/{index.html,module.js} /tmp/test/htdocs/
cp ./samples/cc.conf /tmp/test/
docker run --rm -p 127.0.0.1:8888:80 \
       -v "/tmp/test/htdocs:/usr/local/apache2/htdocs/:ro" \
       -v "/tmp/test/cc.conf:/usr/local/apache2/conf/extra/cc.conf:ro" \
       --entrypoint=/bin/sh httpd -c 'echo "Include conf/extra/cc.conf" >> /usr/local/apache2/conf/httpd.conf && httpd-foreground'
```

Then you can start QEMU on `localhost:8888`.
