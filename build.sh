make tools/llvm-bpf/compile -j1 V=s 2>&1 | tee llvm-bpf.log
make -j$(nproc) V=s 2>&1 | tee build.log
grep -n -B 50 "ERROR: package/.*failed to build" build.log
