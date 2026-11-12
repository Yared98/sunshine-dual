cmake_minimum_required(VERSION 3.21)
project(sunshine_dual LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(SD_BUILD_WIN32 "Build Windows components (proc/session/patcher, needs Zydis)" ON)

# --- Pure, portable pattern-scan core (no Win32, no external deps) ---------
add_library(sd_scan STATIC src/signature.cpp)
target_include_directories(sd_scan PUBLIC ${CMAKE_SOURCE_DIR}/include)

enable_testing()
add_executable(scan_tests tests/scan_tests.cpp)
target_link_libraries(scan_tests PRIVATE sd_scan)
add_test(NAME scan_tests COMMAND scan_tests)

# --- Windows-only components ----------------------------------------------
# sd_proc and sd_session need no external deps and build with MinGW or MSVC.
if (WIN32 AND SD_BUILD_WIN32)
  add_library(sd_proc STATIC src/procmem.cpp)
  target_include_directories(sd_proc PUBLIC ${CMAKE_SOURCE_DIR}/include)

  add_library(sd_session STATIC src/session.cpp)
  target_include_directories(sd_session PUBLIC ${CMAKE_SOURCE_DIR}/include)
  target_link_libraries(sd_session PUBLIC wtsapi32 netapi32 userenv advapi32)

  # The patcher + orchestrator CLI. Built on request. Zydis (optional, for
  # disassembly-level validation) is added only if found, so the default build
  # needs no vcpkg.
  option(SD_BUILD_PATCHER "Build sd_patch + orchestrator exe" OFF)
  if (SD_BUILD_PATCHER)
    add_library(sd_patch STATIC src/patcher.cpp)
    target_include_directories(sd_patch PUBLIC ${CMAKE_SOURCE_DIR}/include)
    target_link_libraries(sd_patch PUBLIC sd_scan sd_proc)

    find_package(Zydis CONFIG QUIET)
    if (Zydis_FOUND)
      target_link_libraries(sd_patch PUBLIC Zydis::Zydis)
      target_compile_definitions(sd_patch PUBLIC SD_HAVE_ZYDIS=1)
    endif()

    add_executable(sunshine_dual src/main.cpp)
    target_link_libraries(sunshine_dual PRIVATE sd_patch sd_session)
    # MinGW needs -municode so wmain() is used as the entry point.
    # Link the MinGW runtime statically so the exe is self-contained: it must run
    # as SYSTEM (boot task) and in clean shells with no MinGW DLLs on PATH.
    # Without this it fails to load with 0xC0000135 (DLL not found) /
    # 0xC0000139 (entry point not found).
    target_compile_options(sunshine_dual PRIVATE -municode)
    target_link_options(sunshine_dual PRIVATE -municode -static -static-libgcc -static-libstdc++)
  endif()
endif()
