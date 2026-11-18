#!/bin/sh
# Downloads the Kokoro-82M v1.0 ONNX model and voices (Apache-2.0) from the
# kokoro-onnx GitHub release into DIR (default ./models) and checks the pinned SHA-256 sums.
# Usage: services/tts/fetch-models.sh [DIR]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dir=${1:-models}
base=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0

mkdir -p "$dir"
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  if [ ! -s "$dir/$f" ]; then
    curl -fL --retry 3 -o "$dir/$f.part" "$base/$f"
    mv "$dir/$f.part" "$dir/$f"
  fi
done
(cd "$dir" && sha256sum -c "$here/models.sha256")
