cmake_minimum_required(VERSION 3.22.1)
project("keqdroid_native")

add_library(keqdroid_native SHARED forkexec.c)
target_link_libraries(keqdroid_native log)