# Zig Build for libsrtp

This project supports building with Zig as an alternative to meson/cmake/autotools.

## Quick Start

```bash
zig build
```

## Cross-Compilation

Zig makes cross-compilation trivial:

```bash
# Build for Windows
zig build -Dtarget=x86_64-windows-gnu

# Build for macOS ARM64
zig build -Dtarget=aarch64-macos-none

# Build for WebAssembly
zig build -Dtarget=wasm32-wasi-musl

# Build for RISC-V
zig build -Dtarget=riscv64-linux-gnu
```

## Build Options

### Logging Options

```bash
# Enable debug logging
zig build -Ddebug-logging=true

# Redirect logs to stdout
zig build -Dlog-stdout=true

# Write logs to a file
zig build -Dlog-file=/var/log/srtp.log
```

### Crypto Library Selection

By default, libsrtp uses its internal crypto implementation. You can choose an external library:

```bash
# Use OpenSSL
zig build -Dcrypto-library=openssl

# Use Mozilla NSS
zig build -Dcrypto-library=nss

# Use Mbed TLS
zig build -Dcrypto-library=mbedtls
```

**Note:** External crypto libraries must be installed on your system.

## Supported Targets

- Linux: x86_64, x86, arm, aarch64, mips, riscv32, riscv64, loongarch64
- Windows: x86_64, x86, aarch64
- macOS: x86_64, aarch64 (Apple Silicon)
- WebAssembly: wasm32-wasi
- Android: arm, aarch64 (requires NDK)

## Output

Build artifacts are placed in `zig-out/`:
- `zig-out/lib/libsrtp2.a` - Static library
- `zig-out/include/srtp2/` - Public headers

## Requirements

- Zig 0.15.2 or later
- For OpenSSL builds: libssl-dev
- For NSS builds: libnss3-dev
- For Mbed TLS builds: libmbedtls-dev
- For Android builds: Android NDK
