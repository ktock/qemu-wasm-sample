# Building QEMU (TCI) with emscripten with 64bit guest support using wasm64

Patch is maintained in https://github.com/ktock/qemu-wasm/pull/29

Assuming this repository and [a patch for 64bit guest support](https://github.com/ktock/qemu-wasm/pull/29) are cloned locally.
Set the current directory to the root directory of this repository.

## Compiling QEMU

Build and start the build environment container.
This contains the following prerequisites.

- Emscripten SDK (emsdk) v4.0.10
- Libraries cross-compiled with Emscripten (please see also emsdk-wasm-cross.docker for build steps)
  - GLib v2.84.0
  - zlib v1.3.1
  - libffi v3.5.2
  - Pixman v0.44.2

This container also contains xterm-pty which is an on-browser terminal emulator integrated with Emscripten.

QEMU can be compiled in either of the following options, depending on the compatibility requirements of the target engine.

### Option 1: Compiling QEMU for wasm64

This section shows steps to compile QEMU for wasm64.
Note that some engines, including Safari, don't support wasm64 as of now.
The adoption status of wasm64 can be seen at https://webassembly.org/features/ .

Set `QEMU_REPO` environment variable to the path of the local QEMU repository with [the patch for 64bit guest support](https://github.com/ktock/qemu-wasm/pull/29).
Run the following command to build the container.

```
QEMU_BUILD_CONTAINER=build-qemu-wasm64
docker build --progress=plain -t build-qemu-base-wasm64 --build-arg TARGET_CPU=wasm64 --build-arg WASM64_MEMORY64=1 - < ${QEMU_REPO}/tests/docker/dockerfiles/emsdk-wasm-cross.docker
docker build --progress=plain -t build-qemu-wasm64 --build-arg QEMU_BASE_IMAGE=build-qemu-base-wasm64 .
docker run --rm --init -d --name ${QEMU_BUILD_CONTAINER} -v ${QEMU_REPO}:/qemu/:ro build-qemu-wasm64
```

`docker exec` command starts the shell in the container.

```
docker exec -it ${QEMU_BUILD_CONTAINER} /bin/bash
```

The following needs to run inside the build environment container.

QEMU can be compiled using Emscripten's emconfigure and emmake, which automatically set environment variables such as CC for targeting Emscripten.
QEMU's configure script supports `--cpu=wasm64` flag to compile QEMU with 64bit pointer support.

```
emconfigure /qemu/configure --cpu=wasm64 --static --disable-tools \
                            --target-list=x86_64-softmmu --enable-tcg-interpreter
emmake make -j$(nproc)
```

This process generates the following files:

- qemu-system-x86_64.js
- qemu-system-x86_64.wasm

### Option 2: Compiling QEMU for wasm64 with compatibility for wasm32 engines

This section shows steps to compile QEMU for wasm64 while still alowing it to run on wasm32 engines, using Emscripten's [`-sMEMORY64=2`](https://emscripten.org/docs/tools_reference/settings_reference.html#memory64).
This flag still enables 64bit pointers in the C code and Emscripten lowers the output to wasm32 with limiting the available memory size to 4GB, which allows QEMU to run on wasm32 engines.

Set `QEMU_REPO` environment variable to the path of the local QEMU repository with [the patch for 64bit guest support](https://github.com/ktock/qemu-wasm/pull/29).
Run the following command to build the container. 
The build arg `WASM64_MEMORY64=2` builds the dependencies with maintaining wasm32 compatibility.

```
QEMU_BUILD_CONTAINER=build-qemu-wasm64l
docker build --progress=plain -t build-qemu-base-wasm64l --build-arg TARGET_CPU=wasm64 --build-arg WASM64_MEMORY64=2 - < ${QEMU_REPO}/tests/docker/dockerfiles/emsdk-wasm-cross.docker
docker build --progress=plain -t build-qemu-wasm64l .
docker run --rm --init -d --name ${QEMU_BUILD_CONTAINER} -v ${QEMU_REPO}:/qemu/:ro build-qemu-wasm64l
```

`docker exec` command starts the shell in the container.

```
docker exec -it ${QEMU_BUILD_CONTAINER} /bin/bash
```

The following needs to run inside the build environment container.

QEMU can be compiled using Emscripten's emconfigure and emmake.
QEMU's configure script supports `--cpu=wasm64` flag to compile QEMU with 64bit pointer support.
`--wasm64-memory64=2` flag enables lowering support.
The value of this flag is propagated to Emscripten's [`-sMEMORY64` flag](https://emscripten.org/docs/tools_reference/settings_reference.html#memory64).

```
emconfigure /qemu/configure --cpu=wasm64 --wasm64-memory64=2 --static --disable-tools \
                            --target-list=x86_64-softmmu --enable-tcg-interpreter
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
docker cp ${QEMU_BUILD_CONTAINER}:/build/qemu-system-x86_64.js /tmp/test/htdocs/out.js
for f in qemu-system-x86_64.wasm qemu-system-x86_64.data load.js ; do
  docker cp ${QEMU_BUILD_CONTAINER}:/build/${f} /tmp/test/htdocs/
done
cp ./samples/{index.html,module.js} /tmp/test/htdocs/
cp ./samples/cc.conf /tmp/test/
docker run --rm -d -p 127.0.0.1:8888:80 \
       -v "/tmp/test/htdocs:/usr/local/apache2/htdocs/:ro" \
       -v "/tmp/test/cc.conf:/usr/local/apache2/conf/extra/cc.conf:ro" \
       --entrypoint=/bin/sh httpd -c 'echo "Include conf/extra/cc.conf" >> /usr/local/apache2/conf/httpd.conf && httpd-foreground'
```

Then you can start QEMU on `localhost:8888`.
