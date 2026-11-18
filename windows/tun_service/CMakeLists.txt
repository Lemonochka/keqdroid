cmake_minimum_required(VERSION 3.14)
project(keqdroid_tun LANGUAGES CXX)

set(KEQ_CORE_DIR "${CMAKE_SOURCE_DIR}/../assets/bin/windows")

# служба запускает только те ядра, что лежали в сборке: их суммы вшиваются сюда.
# новые ядра пересобирают конфигурацию сами
function(keq_core_hash var file)
  set(path "${KEQ_CORE_DIR}/${file}")
  set(hash "")
  if(EXISTS "${path}")
    file(SHA256 "${path}" hash)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${path}")
  endif()
  set(${var} "${hash}" PARENT_SCOPE)
endfunction()

# служба живёт в Program Files одна, без DLL рантайма рядом, а на чистой Windows их нет: рантайм внутрь exe.
# CMP0091 у Flutter старый, поэтому флаги правим в этом каталоге руками
foreach(flag_var
    CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_PROFILE
    CMAKE_CXX_FLAGS_RELEASE CMAKE_CXX_FLAGS_RELWITHDEBINFO
    CMAKE_CXX_FLAGS_MINSIZEREL)
  string(REPLACE "/MD" "/MT" ${flag_var} "${${flag_var}}")
endforeach()

keq_core_hash(KEQ_XRAY_SHA256 xray.exe)
keq_core_hash(KEQ_MIHOMO_SHA256 mihomo.exe)
keq_core_hash(KEQ_WINTUN_SHA256 wintun.dll)
configure_file(core_hashes.h.in "${CMAKE_CURRENT_BINARY_DIR}/core_hashes.h" @ONLY)

add_executable(keqdroid-tun WIN32
  "main.cpp"
  "config_check.cpp"
  "${CMAKE_SOURCE_DIR}/runner/windows_tun_adapters.cpp"
)
apply_standard_settings(keqdroid-tun)
target_compile_options(keqdroid-tun PRIVATE "/utf-8")
target_compile_definitions(keqdroid-tun PRIVATE "NOMINMAX" "UNICODE" "_UNICODE")
target_include_directories(keqdroid-tun PRIVATE
  "${CMAKE_CURRENT_BINARY_DIR}"
  "${CMAKE_SOURCE_DIR}"
)
target_link_libraries(keqdroid-tun PRIVATE
  "advapi32.lib" "bcrypt.lib" "shell32.lib" "ole32.lib"
  "setupapi.lib" "cfgmgr32.lib"
)
