# Any copyright is dedicated to the Public Domain.
# http://creativecommons.org/publicdomain/zero/1.0/

ROOT_DIR=${CURDIR}
#LLVM_PROJECT_SHA=
#MUSL2_SHA=

VERSION=0.2
DEBUG_PREFIX_MAP=-fdebug-prefix-map=$(ROOT_DIR)=wasmception://v$(VERSION)

default: build
	echo "Use --sysroot=$(ROOT_DIR)/sysroot -fdebug-prefix-map=$(ROOT_DIR)=wasmception://v$(VERSION)"

clean:
	rm -rf build src dist sysroot wasmception-*-bin.tar.gz

src/llvm-project.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/llvm/llvm-project.git
	touch src/llvm-project.CLONED

src/musl2.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/sunfishcode/reference-sysroot musl2 -b misc
ifdef MUSL2_SHA
	cd src/musl2; git checkout $(MUSL2_SHA)
endif
	cd src/musl2; patch -p 1 < $(ROOT_DIR)/patches/musl2.1.patch
	touch src/musl2.CLONED

build/llvm.BUILT: src/llvm-project.CLONED
	mkdir -p build/llvm
	cd build/llvm; cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX=$(ROOT_DIR)/dist \
		-DLLVM_TARGETS_TO_BUILD= \
		-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly \
		-DLLVM_EXTERNAL_CLANG_SOURCE_DIR=$(ROOT_DIR)/src/llvm-project/clang \
		-DLLVM_EXTERNAL_LLD_SOURCE_DIR=$(ROOT_DIR)/src/llvm-project/lld \
		-DLLVM_ENABLE_PROJECTS="lld;clang" \
		$(ROOT_DIR)/src/llvm-project/llvm
	cd build/llvm; $(MAKE) -j 8 \
		install-clang \
		install-lld \
		install-llc \
		install-llvm-ar \
		install-llvm-ranlib \
		install-llvm-dwarfdump \
		install-clang-headers \
		install-llvm-nm \
		llvm-config
	touch build/llvm.BUILT

build/musl2.BUILT: src/musl2.CLONED build/llvm.BUILT
	cp -R $(ROOT_DIR)/src/musl2 build/musl2
	make -C build/musl2 \
		WASM_CC=$(ROOT_DIR)/dist/bin/clang
	mkdir -p sysroot
	cp -R build/musl2/sysroot/* sysroot
	touch build/musl2.BUILT

build/compiler-rt.BUILT: src/llvm-project.CLONED build/llvm.BUILT
	mkdir -p build/compiler-rt
	cd build/compiler-rt; cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DCOMPILER_RT_BAREMETAL_BUILD=On \
		-DCOMPILER_RT_BUILD_XRAY=OFF \
		-DCOMPILER_RT_INCLUDE_TESTS=OFF \
		-DCOMPILER_RT_ENABLE_IOS=OFF \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=On \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm -O1 $(DEBUG_PREFIX_MAP)" \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCOMPILER_RT_OS_DIR=. \
		-DCMAKE_INSTALL_PREFIX=$(ROOT_DIR)/dist/lib/clang/9.0.0/ \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		$(ROOT_DIR)/src/llvm-project/compiler-rt/lib/builtins
	cd build/compiler-rt; make -j 8 install
	cp -R $(ROOT_DIR)/build/llvm/lib/clang $(ROOT_DIR)/dist/lib/
	touch build/compiler-rt.BUILT

build/libcxx.BUILT: build/llvm.BUILT src/llvm-project.CLONED build/compiler-rt.BUILT build/musl2.BUILT
	mkdir -p build/libcxx
	cd build/libcxx; cmake -G "Unix Makefiles" \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		-DLIBCXX_ENABLE_THREADS:BOOL=OFF \
		-DLIBCXX_ENABLE_STDIN:BOOL=OFF \
		-DLIBCXX_ENABLE_STDOUT:BOOL=OFF \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXX_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY:BOOL=OFF \
		-DLIBCXX_ENABLE_FILESYSTEM:BOOL=OFF \
		-DLIBCXX_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXX_ENABLE_RTTI:BOOL=OFF \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXX_CXX_ABI_INCLUDE_PATHS=$(ROOT_DIR)/src/llvm-project/libcxxabi/include \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP)" \
		-DCMAKE_CXX_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP) -D_LIBCPP_HAS_MUSL_LIBC" \
		--debug-trycompile \
		$(ROOT_DIR)/src/llvm-project/libcxx
	cd build/libcxx; make -j 8 install
	touch build/libcxx.BUILT

build/libcxxabi.BUILT: src/llvm-project.CLONED build/libcxx.BUILT build/llvm.BUILT
	mkdir -p build/libcxxabi
	cd build/libcxxabi; cmake -G "Unix Makefiles" \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		-DCMAKE_CXX_COMPILER_WORKS=ON \
		-DCMAKE_C_COMPILER_WORKS=ON \
		-DLIBCXXABI_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXXABI_ENABLE_THREADS:BOOL=OFF \
		-DCXX_SUPPORTS_CXX11=ON \
		-DLLVM_COMPILER_CHECKED=ON \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXXABI_LIBCXX_PATH=$(ROOT_DIR)/src/llvm-project/libcxx \
		-DLIBCXXABI_LIBCXX_INCLUDES=$(ROOT_DIR)/sysroot/include/c++/v1 \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP)" \
		-DCMAKE_CXX_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP) -D_LIBCPP_HAS_MUSL_LIBC" \
		-DUNIX:BOOL=ON \
		--debug-trycompile \
		$(ROOT_DIR)/src/llvm-project/libcxxabi
	cd build/libcxxabi; make -j 8 install
	touch build/libcxxabi.BUILT

BASICS=sysroot/include/wasmception.h sysroot/lib/wasmception.wasm

sysroot/include/wasmception.h: basics/wasmception.h
	cp basics/wasmception.h sysroot/include/

sysroot/lib/wasmception.wasm: build/llvm.BUILT basics/wasmception.c
	dist/bin/clang \
		--target=wasm32-unknown-unknown-wasm \
		--sysroot=./sysroot basics/wasmception.c \
		-c -O3 -g $(DEBUG_PREFIX_MAP) \
		-o sysroot/lib/wasmception.wasm

build: build/llvm.BUILT build/musl2.BUILT build/compiler-rt.BUILT build/libcxxabi.BUILT build/libcxx.BUILT $(BASICS)

strip: build/llvm.BUILT
	cd dist/bin; strip clang-8 llc lld llvm-ar

collect-sources:
	-rm -rf build/sources build/sources.txt
	{ find sysroot -name "*.o"; find sysroot -name "*.wasm"; find dist/lib sysroot -name "lib*.a"; } | \
	  xargs ./list_debug_sources.py | sort > build/sources.txt
	echo "sysroot/include" >> build/sources.txt
	for f in $$(cat build/sources.txt); \
	  do mkdir -p `dirname build/sources/$$f`; cp -R $$f `dirname build/sources/$$f`; done;
	cd build/sources && { git init; git checkout --orphan v$(VERSION); git add -A .; git commit -m "Sources"; }
	echo "cd build/sources && git push -f git@github.com:yurydelendik/wasmception.git v$(VERSION)"

revisions:
	cd src/livm-project; echo "LLVM_PROJECT_REV=`git log -1 --format="%H"`"
	cd src/musl2; echo "MUSL2_SHA=`git log -1 --format="%H"`"

OS_NAME=$(shell uname -s | tr '[:upper:]' '[:lower:]')
pack:
	tar czf wasmception-${OS_NAME}-bin.tar.gz dist sysroot

.PHONY: default clean build strip revisions pack collect-sources
