const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Options
    const debug_logging = b.option(bool, "debug-logging", "Enable debug logging in all modules") orelse false;
    const log_stdout = b.option(bool, "log-stdout", "Redirect logging to stdout") orelse false;
    const log_file = b.option([]const u8, "log-file", "Write logging output into this file") orelse "";
    
    const CryptoLib = enum { none, openssl, nss, mbedtls };
    const crypto_library = b.option(CryptoLib, "crypto-library", "What external crypto library to leverage") orelse .none;
    
    const lib = b.addLibrary(.{
        .name = "srtp2",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.linkage = .static;

    lib.linkLibC();

    var sources = std.ArrayListUnmanaged([]const u8){};
    // defer sources.deinit(b.allocator);

    // Core sources
    sources.appendSlice(b.allocator, &[_][]const u8{
        "srtp/srtp.c",
        "crypto/kernel/alloc.c",
        "crypto/kernel/crypto_kernel.c",
        "crypto/kernel/err.c",
        "crypto/kernel/key.c",
        "crypto/math/datatypes.c",
        "crypto/replay/rdb.c",
        "crypto/replay/rdbx.c",
    }) catch @panic("OOM");

    // Cipher sources
    sources.appendSlice(b.allocator, &[_][]const u8{
        "crypto/cipher/cipher.c",
        "crypto/cipher/cipher_test_cases.c",
        "crypto/cipher/null_cipher.c",
    }) catch @panic("OOM");

    // Hash sources
    sources.appendSlice(b.allocator, &[_][]const u8{
        "crypto/hash/auth.c",
        "crypto/hash/auth_test_cases.c",
        "crypto/hash/null_auth.c",
    }) catch @panic("OOM");

    var c_flags = std.ArrayListUnmanaged([]const u8){};
    // defer c_flags.deinit(b.allocator);
    c_flags.append(b.allocator, "-DHAVE_CONFIG_H") catch @panic("OOM");
    c_flags.append(b.allocator, "-Wstrict-prototypes") catch @panic("OOM");
    
    if (optimize != .Debug) {
        c_flags.append(b.allocator, "-funroll-loops") catch @panic("OOM");
    }

    // Handle Options
    if (debug_logging) {
        c_flags.append(b.allocator, "-DENABLE_DEBUG_LOGGING") catch @panic("OOM");
    }
    if (log_stdout) {
        c_flags.append(b.allocator, "-DERR_REPORTING_STDOUT") catch @panic("OOM");
    }
    if (log_file.len > 0) {
        const def = b.fmt("-DERR_REPORTING_FILE=\"{s}\"", .{log_file});
        c_flags.append(b.allocator, def) catch @panic("OOM");
    }

    // Crypto Library Selection
    switch (crypto_library) {
        .openssl => {
            c_flags.append(b.allocator, "-DGCM") catch @panic("OOM");
            c_flags.append(b.allocator, "-DOPENSSL") catch @panic("OOM");
            c_flags.append(b.allocator, "-DUSE_EXTERNAL_CRYPTO") catch @panic("OOM");
            c_flags.append(b.allocator, "-DOPENSSL_KDF") catch @panic("OOM");
            
            sources.appendSlice(b.allocator, &[_][]const u8{
                "crypto/cipher/aes_icm_ossl.c",
                "crypto/cipher/aes_gcm_ossl.c",
                "crypto/hash/hmac_ossl.c",
            }) catch @panic("OOM");
            
            lib.linkSystemLibrary("openssl");
            lib.linkSystemLibrary("crypto");
        },
        .nss => {
            c_flags.append(b.allocator, "-DGCM") catch @panic("OOM");
            c_flags.append(b.allocator, "-DNSS") catch @panic("OOM");
            c_flags.append(b.allocator, "-DUSE_EXTERNAL_CRYPTO") catch @panic("OOM");
            
            sources.appendSlice(b.allocator, &[_][]const u8{
                "crypto/cipher/aes_icm_nss.c",
                "crypto/cipher/aes_gcm_nss.c",
                "crypto/hash/hmac_nss.c",
            }) catch @panic("OOM");
            
            lib.linkSystemLibrary("nss3");
        },
        .mbedtls => {
            c_flags.append(b.allocator, "-DGCM") catch @panic("OOM");
            c_flags.append(b.allocator, "-DMBEDTLS") catch @panic("OOM");
            c_flags.append(b.allocator, "-DUSE_EXTERNAL_CRYPTO") catch @panic("OOM");
            
            sources.appendSlice(b.allocator, &[_][]const u8{
                "crypto/cipher/aes_icm_mbedtls.c",
                "crypto/cipher/aes_gcm_mbedtls.c",
                "crypto/hash/hmac_mbedtls.c",
            }) catch @panic("OOM");
            
            lib.linkSystemLibrary("mbedcrypto");
        },
        .none => {
            sources.appendSlice(b.allocator, &[_][]const u8{
                "crypto/cipher/aes.c",
                "crypto/cipher/aes_icm.c",
                "crypto/hash/hmac.c",
                "crypto/hash/sha1.c",
            }) catch @panic("OOM");
        },
    }

    lib.root_module.addCSourceFiles(.{
        .files = sources.items,
        .flags = c_flags.items,
    });

    lib.root_module.addIncludePath(b.path("."));
    lib.root_module.addIncludePath(b.path("include"));
    lib.root_module.addIncludePath(b.path("crypto/include"));

    // Generate config.h
    const config_h = generateConfigH(b, target, debug_logging, log_stdout, log_file, crypto_library);
    const config_file = b.addWriteFile("config.h", config_h);
    lib.root_module.addIncludePath(config_file.getDirectory());

    // Public headers
    const public_headers = b.addWriteFiles();
    _ = public_headers.addCopyFile(b.path("include/srtp.h"), "srtp2/srtp.h");
    _ = public_headers.addCopyFile(b.path("crypto/include/auth.h"), "srtp2/auth.h");
    _ = public_headers.addCopyFile(b.path("crypto/include/cipher.h"), "srtp2/cipher.h");
    _ = public_headers.addCopyFile(b.path("crypto/include/crypto_types.h"), "srtp2/crypto_types.h");
    
    lib.root_module.addIncludePath(public_headers.getDirectory());
    lib.installHeadersDirectory(public_headers.getDirectory(), ".", .{});

    b.installArtifact(lib);
}

fn generateConfigH(b: *std.Build, target: std.Build.ResolvedTarget, debug_logging: bool, log_stdout: bool, log_file: []const u8, crypto_lib: anytype) []const u8 {
    var config = std.ArrayListUnmanaged(u8){};
    const writer = config.writer(b.allocator);

    writer.print(
        \\#define PACKAGE_VERSION "2.7.0"
        \\#define PACKAGE_STRING "libsrtp2 2.7.0"
        \\#define PACKAGE_NAME "libsrtp2"
        \\#define PACKAGE_TARNAME "libsrtp2"
        \\#define PACKAGE_URL ""
        \\#define PACKAGE_BUGREPORT ""
        \\
        \\#define HAVE_STDINT_H 1
        \\#define HAVE_STDLIB_H 1
        \\#define HAVE_STRING_H 1
        \\#define HAVE_INTTYPES_H 1
        \\#define HAVE_MEMORY_H 1
        \\#define HAVE_SYS_TYPES_H 1
        \\#define HAVE_INT8_T 1
        \\#define HAVE_UINT8_T 1
        \\#define HAVE_INT16_T 1
        \\#define HAVE_UINT16_T 1
        \\#define HAVE_INT32_T 1
        \\#define HAVE_UINT32_T 1
        \\#define HAVE_UINT64_T 1
        \\
    , .{}) catch @panic("OOM");

    const t = target.result;

    if (t.cpu.arch.endian() == .big) {
        writer.print("#define WORDS_BIGENDIAN 1\n", .{}) catch @panic("OOM");
    }

    if (t.cpu.arch == .x86 or t.cpu.arch == .x86_64) {
        writer.print(
            \\#define CPU_CISC 1
            \\#define HAVE_X86 1
            \\
        , .{}) catch @panic("OOM");
    } else {
        writer.print("#define CPU_RISC 1\n", .{}) catch @panic("OOM");
    }

    if (t.os.tag == .windows) {
        writer.print(
            \\#define HAVE_WINDOWS_H 1
            \\#define HAVE_WINSOCK2_H 1
            \\
        , .{}) catch @panic("OOM");
    } else {
        writer.print(
            \\#define HAVE_ARPA_INET_H 1
            \\#define HAVE_NETINET_IN_H 1
            \\#define HAVE_SYS_SOCKET_H 1
            \\#define HAVE_SYS_UIO_H 1
            \\#define HAVE_UNISTD_H 1
            \\#define HAVE_INET_ATON 1
            \\#define HAVE_SIGACTION 1
            \\#define HAVE_SOCKET 1
            \\#define HAVE_USLEEP 1
            \\
        , .{}) catch @panic("OOM");
    }
    
    // Sizes
    const ptr_width = t.ptrBitWidth();
    const long_size = if (t.os.tag == .windows) 4 else ptr_width / 8;
    const long_long_size = 8;
    
    writer.print("#define SIZEOF_UNSIGNED_LONG {d}\n", .{long_size}) catch @panic("OOM");
    writer.print("#define SIZEOF_UNSIGNED_LONG_LONG {d}\n", .{long_long_size}) catch @panic("OOM");

    // Options
    if (debug_logging) writer.print("#define ENABLE_DEBUG_LOGGING 1\n", .{}) catch @panic("OOM");
    if (log_stdout) writer.print("#define ERR_REPORTING_STDOUT 1\n", .{}) catch @panic("OOM");
    if (log_file.len > 0) writer.print("#define ERR_REPORTING_FILE \"{s}\"\n", .{log_file}) catch @panic("OOM");

    switch (crypto_lib) {
        .openssl => {
            writer.print("#define OPENSSL 1\n#define GCM 1\n#define USE_EXTERNAL_CRYPTO 1\n#define OPENSSL_KDF 1\n", .{}) catch @panic("OOM");
        },
        .nss => {
            writer.print("#define NSS 1\n#define GCM 1\n#define USE_EXTERNAL_CRYPTO 1\n", .{}) catch @panic("OOM");
        },
        .mbedtls => {
            writer.print("#define MBEDTLS 1\n#define GCM 1\n#define USE_EXTERNAL_CRYPTO 1\n", .{}) catch @panic("OOM");
        },
        .none => {},
    }

    return config.toOwnedSlice(b.allocator) catch @panic("OOM");
}
