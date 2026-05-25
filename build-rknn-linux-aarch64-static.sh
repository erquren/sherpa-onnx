#!/usr/bin/env bash
#
# Build sherpa-onnx as a STATIC library (.a) for RKNN on Linux aarch64.
#
# Prerequisites:
#   1. Clone rknn-toolkit2:
#        git clone --depth 1 https://github.com/airockchip/rknn-toolkit2
#      Or set SHERPA_ONNX_RKNN_TOOLKIT2_PATH to its location.
#
#   2. Install the aarch64 cross-compilation toolchain:
#        sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
#
#   3. Install build dependencies for alsa-lib:
#        sudo apt-get install libtool m4 automake
#
# Usage:
#   ./build-rknn-linux-aarch64-static.sh
#
# Output:
#   build-rknn-linux-aarch64-static/install/lib/libsherpa-onnx*.a
#   build-rknn-linux-aarch64-static/install/bin/sherpa-onnx*
#

set -ex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -------- Locate rknn-toolkit2 --------
if [ -z "$SHERPA_ONNX_RKNN_TOOLKIT2_PATH" ]; then
  SHERPA_ONNX_RKNN_TOOLKIT2_PATH="$PWD/rknn-toolkit2"
fi

if [ ! -d "$SHERPA_ONNX_RKNN_TOOLKIT2_PATH" ]; then
  echo "ERROR: rknn-toolkit2 not found at $SHERPA_ONNX_RKNN_TOOLKIT2_PATH"
  echo "Please clone it first:"
  echo "  git clone --depth 1 https://github.com/airockchip/rknn-toolkit2"
  exit 1
fi

RKNN_INCLUDE="$SHERPA_ONNX_RKNN_TOOLKIT2_PATH/rknpu2/runtime/Linux/librknn_api/include"
RKNN_LIB="$SHERPA_ONNX_RKNN_TOOLKIT2_PATH/rknpu2/runtime/Linux/librknn_api/aarch64"

if [ ! -f "$RKNN_INCLUDE/rknn_api.h" ]; then
  echo "ERROR: $RKNN_INCLUDE/rknn_api.h does not exist"
  exit 1
fi

if [ ! -f "$RKNN_LIB/librknnrt.so" ]; then
  echo "ERROR: $RKNN_LIB/librknnrt.so does not exist"
  exit 1
fi

export SHERPA_ONNX_RKNN_TOOLKIT2_PATH
export SHERPA_ONNX_RKNN_TOOLKIT2_LIB_DIR="$RKNN_LIB"
export CPLUS_INCLUDE_PATH="$RKNN_INCLUDE:$CPLUS_INCLUDE_PATH"

# -------- Check cross-compiler --------
if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
  echo "ERROR: aarch64-linux-gnu-gcc not found."
  echo "Please install the cross-compilation toolchain:"
  echo "  sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
  echo ""
  echo "See also: https://k2-fsa.github.io/sherpa/onnx/install/rknn-linux-aarch64.html"
  exit 1
fi

# -------- Build directory --------
BUILD_DIR="$PWD/build-rknn-linux-aarch64-static"
mkdir -p "$BUILD_DIR"

# -------- Cross-compile alsa-lib --------
if [ ! -f "$BUILD_DIR/alsa-lib/src/.libs/libasound.so" ]; then
  echo "=== Cross-compiling alsa-lib ==="
  if [ ! -d "$BUILD_DIR/alsa-lib" ]; then
    git clone --depth 1 --branch v1.2.12 https://github.com/alsa-project/alsa-lib "$BUILD_DIR/alsa-lib"
  fi

  pushd "$BUILD_DIR/alsa-lib"
  CC=aarch64-linux-gnu-gcc ./gitcompile --host=aarch64-linux-gnu
  popd
  echo "=== Finished cross-compiling alsa-lib ==="
fi

export CPLUS_INCLUDE_PATH="$BUILD_DIR/alsa-lib/include:$CPLUS_INCLUDE_PATH"
export SHERPA_ONNX_ALSA_LIB_DIR="$BUILD_DIR/alsa-lib/src/.libs"

# -------- CMake configure --------
cd "$BUILD_DIR"

cmake \
  -DALSA_INCLUDE_DIR="$BUILD_DIR/alsa-lib/include" \
  -DALSA_LIBRARY="$BUILD_DIR/alsa-lib/src/.libs/libasound.so" \
  -DBUILD_PIPER_PHONMIZE_EXE=OFF \
  -DBUILD_PIPER_PHONMIZE_TESTS=OFF \
  -DBUILD_ESPEAK_NG_EXE=OFF \
  -DBUILD_ESPEAK_NG_TESTS=OFF \
  -DCMAKE_INSTALL_PREFIX=./install \
  -DCMAKE_BUILD_TYPE=Release \
  -DSHERPA_ONNX_ENABLE_GPU=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=ON \
  -DSHERPA_ONNX_ENABLE_JNI=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=ON \
  -DSHERPA_ONNX_ENABLE_RKNN=ON \
  -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/toolchains/aarch64-linux-gnu.toolchain.cmake" \
  "$SCRIPT_DIR"

# -------- Build --------
make VERBOSE=1 -j$(nproc)
make install/strip

# -------- Summary --------
echo ""
echo "============================================"
echo " Build completed successfully!"
echo "============================================"
echo ""
echo "Static library:"
ls -lh install/lib/libsherpa-onnx*.a 2>/dev/null || ls -lh install/lib/*.a
echo ""
echo "Binaries:"
ls -lh install/bin/
echo ""
echo "Info:"
file install/bin/sherpa-onnx 2>/dev/null || file install/bin/sherpa-onnx-offline 2>/dev/null || true
echo ""
echo "Output directory: $BUILD_DIR/install"
