# clkh: a headless Acorn Electron on Clock Signal's (CLK) core, for the
# harness (README.md). The CLK tree is used read-only; its Electron machine
# is compiled from this folder's copy (Electron.cpp), which adds the
# harness's counters and hooks.
cmake_minimum_required(VERSION 3.19 FATAL_ERROR)
project(clkh LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE Release)
endif()

set(CLK_ROOT "$ENV{HOME}/cleo_electron/electron/clk" CACHE PATH "Clock Signal's source tree (read-only)")
if(NOT EXISTS "${CLK_ROOT}/cmake/CLK_SOURCES.cmake")
	message(FATAL_ERROR "CLK_ROOT (${CLK_ROOT}) is not a Clock Signal tree: cmake -DCLK_ROOT=...")
endif()
include(${CLK_ROOT}/cmake/CLK_SOURCES.cmake)

# Everything but the front ends, the OpenGL output and the Electron machine
# (main.cpp compiles this folder's copy, to reach its state).
set(SOURCES main.cpp)
foreach(src ${CLK_SOURCES})
	if(src MATCHES "^OSBindings/" OR src MATCHES "^Outputs/OpenGL/")
		continue()
	endif()
	if(src MATCHES "^Machines/" AND NOT (src MATCHES "^Machines/Acorn/Electron/" OR src MATCHES "^Machines/Acorn/Floppy/" OR src MATCHES "^Machines/Utility/" OR src MATCHES "^Machines/[A-Za-z]*\\.cpp$"))
		continue()
	endif()
	if(src STREQUAL "Machines/Acorn/Electron/Electron.cpp" OR src STREQUAL "Machines/Utility/MachineForTarget.cpp")
		continue()
	endif()
	list(APPEND SOURCES ${CLK_ROOT}/${src})
endforeach()

add_executable(clkh ${SOURCES})
target_include_directories(clkh PRIVATE ${CLK_ROOT})
# (the copy's own includes, "Video.hpp" and the like, are the CLK tree's)
set_source_files_properties(main.cpp PROPERTIES INCLUDE_DIRECTORIES "${CLK_ROOT}/Machines/Acorn/Electron")
target_compile_options(clkh PRIVATE -w)
find_package(ZLIB REQUIRED)
target_link_libraries(clkh PRIVATE ZLIB::ZLIB)
if(APPLE)
	set(BLA_VENDOR Apple)
	find_package(BLAS REQUIRED)
	target_link_libraries(clkh PRIVATE BLAS::BLAS)
endif()
target_compile_definitions(clkh PRIVATE CLK_HEADLESS)
