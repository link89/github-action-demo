# Import the complete conda-forge Protobuf target set before framework configs
# can define a partial protobuf:: target set of their own.
set(Protobuf_DIR "/usr/local/lib/cmake/protobuf" CACHE PATH "Conda Protobuf config")
find_package(Protobuf CONFIG REQUIRED)
