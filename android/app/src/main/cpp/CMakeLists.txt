cmake_minimum_required(VERSION 3.22.1)
project("keqdis_native")

add_library(keqdis_native SHARED forkexec.c)
target_link_libraries(keqdis_native log)