#!/usr/bin/env python3
"""Run standalone C++ gate commands with the Windows ClangCL build configuration."""

import os
import re
import shlex
import subprocess
import sys
from pathlib import Path


def read_flags(path: Path, key: str) -> list[str]:
    prefix = key + " ="
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(prefix):
            return shlex.split(line[len(prefix):], posix=True)
    return []


def native_path(value: str) -> str:
    if re.match(r"^/[A-Za-z]/", value):
        return value[1].upper() + ":/" + value[3:]
    if value == "/tmp" or value.startswith("/tmp/"):
        root = os.environ.get("RIPWIRE_NATIVE_TMP", os.environ.get("TEMP", ""))
        return root.rstrip("/\\") + value[4:]
    if re.match(r"^[A-Za-z]:[^/\\]", value):
        return value[0].upper() + ":/" + value[2:]
    return value.replace("/", "\\") if re.match(r"^[A-Za-z]:/", value) else value


def normalize_flag(value: str) -> str:
    if value.startswith("-I") and len(value) > 2:
        return "/I" + native_path(value[2:])
    if value.startswith("/I") and len(value) > 2:
        return "/I" + native_path(value[2:])
    if value.startswith("/") or re.match(r"^[A-Za-z]:", value):
        return native_path(value)
    return value


def main() -> int:
    real_cxx = os.environ.get("RIPWIRE_CXX_REAL", "")
    flags_file = Path(os.environ.get("RIPWIRE_CXX_FLAGS_MK", ""))
    build_dir = Path(os.environ.get("RIPWIRE_CXX_BUILD_DIR", ""))
    root = Path(os.environ.get("RIPWIRE_NATIVE_ROOT", ""))
    if not real_cxx or not flags_file.is_file():
        print("windows-cxx-driver: compiler or flags.make unavailable", file=sys.stderr)
        return 2

    base = read_flags(flags_file, "CXX_FLAGS")
    base += read_flags(flags_file, "CXX_DEFINES")
    base += read_flags(flags_file, "CXX_INCLUDES")
    base = [normalize_flag(arg) for arg in base]
    if not any(arg.startswith(("/clang:-std=", "/std:", "-std=")) for arg in base):
        base.append("/clang:-std=c++23")
    if "/EHsc" not in base:
        base.append("/EHsc")
    if "/permissive-" not in base:
        base.append("/permissive-")
    if "/utf-8" not in base:
        base.append("/utf-8")
    platform_header = root / "src" / "infra" / "platform_compat.h"
    if platform_header.is_file() and not any("platform_compat.h" in arg for arg in base):
        base += ["/FI", str(platform_header)]

    translated: list[str] = []
    compile_only = False
    syntax_only = False
    output: str | None = None
    i = 0
    while i < len(sys.argv[1:]):
        arg = sys.argv[1:][i]
        if arg in ("-c", "/c", "-E", "/E", "-S", "/S"):
            compile_only = True
            translated.append("/c" if arg in ("-c", "/c") else arg)
        elif arg in ("-fsyntax-only",):
            syntax_only = True
            translated.append("/clang:-fsyntax-only")
        elif arg in ("-std=c++23", "-std=c++2b"):
            pass
        elif arg in ("-O2", "-O3"):
            translated.append("/O2")
        elif arg == "-O0":
            translated.append("/Od")
        elif arg == "-g":
            translated.append("/Zi")
        elif arg in ("-Wall", "-Wextra"):
            translated.append("/W4")
        elif arg == "-I" and i + 1 < len(sys.argv[1:]):
            i += 1
            translated.append("/I" + native_path(sys.argv[1:][i]))
        elif arg == "-o" and i + 1 < len(sys.argv[1:]):
            i += 1
            output = native_path(sys.argv[1:][i])
        elif arg.startswith("-o") and len(arg) > 2:
            output = native_path(arg[2:])
        elif arg in ("-pthread", "-fPIC", "-fPIE"):
            pass
        else:
            translated.append(normalize_flag(arg))
        i += 1

    if output:
        translated += ["/Fo" + output if compile_only or syntax_only else "/Fe:" + output]

    linking = not compile_only and not syntax_only
    if linking:
        compat_cpp = root / "src" / "infra" / "platform_compat.cpp"
        if compat_cpp.is_file() and not any("platform_compat.cpp" in arg for arg in translated):
            translated.append(str(compat_cpp))
        link_flags: list[str] = []
        cache = build_dir / "CMakeCache.txt"
        if cache.is_file():
            for line in cache.read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith(("CMAKE_EXE_LINKER_FLAGS:STRING=", "CMAKE_EXE_LINKER_FLAGS_RELEASE:STRING=")):
                    link_flags += [normalize_flag(arg) for arg in shlex.split(line.split("=", 1)[1], posix=True)]
        if any("-flto" in arg for arg in base):
            base.append("/clang:-fuse-ld=lld")
        translated += ["/link", *link_flags, "ws2_32.lib"]

    return subprocess.run([real_cxx, *base, *translated]).returncode


if __name__ == "__main__":
    raise SystemExit(main())
