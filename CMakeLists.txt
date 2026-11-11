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

  # The patcher pulls in Zydis (via vcpkg) and the final exe; built on request.
  option(SD_BUILD_PATCHER "Build sd_patch + orchestrator exe (needs Zydis)" OFF)
  if (SD_BUILD_PATCHER)
    find_package(Zydis CONFIG REQUIRED)

    add_library(sd_patch STATIC src/patcher.cpp)
    target_include_directories(sd_patch PUBLIC ${CMAKE_SOURCE_DIR}/include)
    target_link_libraries(sd_patch PUBLIC sd_scan sd_proc Zydis::Zydis)

    add_executable(sunshine_dual src/main.cpp)
    target_link_libraries(sunshine_dual PRIVATE sd_patch sd_session)
  endif()
endif()
