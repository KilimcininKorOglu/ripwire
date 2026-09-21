# cmake/Windows.cmake — what a native Windows build (clang-cl, MSVC ABI) adds, in one place.
#
# Included from CMakeLists.txt on Windows only; off Windows, CMakeLists.txt defines ripwire_windows_target() as an
# empty function, so every target calls it unconditionally and no target block carries its own if(WIN32).
#
# Nothing here is a force-include: every operating-system difference in src/ is an os:: call declared by
# src/infra/os.h, and its Windows body is src/infra/os_win32.cpp — the one translation unit that includes
# <windows.h> — which ripwire_windows_target() adds to each target.

# The UCRT deprecates the C library's portable spellings (fopen, strerror, getenv) in favour of _s variants; the
# program uses the portable ones on every platform.
add_compile_definitions(_CRT_SECURE_NO_WARNINGS)

function(ripwire_windows_target tgt)
  target_sources(${tgt} PRIVATE
    "${PROJECT_SOURCE_DIR}/src/infra/os_win32.cpp"
    # longPathAware and activeCodePage=UTF-8. Long paths ALSO need the machine's LongPathsEnabled registry value; the
    # UTF-8 code page reaches the UCRT's narrow file calls only if the probe in the D2 report says so.
    "${PROJECT_SOURCE_DIR}/src/infra/win32/ripwire.manifest")
  # ws2_32: sockets; advapi32: tokens, SIDs, ACLs; shell32: CommandLineToArgvW.
  target_link_libraries(${tgt} PRIVATE ws2_32 advapi32 shell32)
  if(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    target_compile_options(${tgt} PRIVATE /EHsc)
  endif()
endfunction()
