#!/bin/zsh
set -eu
PROJECT_DIR="${0:A:h}"
mkdir -p "$PROJECT_DIR/.build"
xcrun clang++ -std=c++20 -O2 "$PROJECT_DIR/Tests/DSPTests.cpp" -o "$PROJECT_DIR/.build/dsp-tests"
"$PROJECT_DIR/.build/dsp-tests"
