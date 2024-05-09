#!/usr/bin/env bash

alias fd="docker run\
    -it --rm -v $(pwd):/workspace -w /workspace \
    --privileged --device /dev/fuse --security-opt label:disable \
    -u $(id -u):$(id -g) \
    fedora_build"