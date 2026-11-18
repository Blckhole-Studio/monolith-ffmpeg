#!/bin/bash
# Builds the FFmpeg libraries that Monolith's software decoders use. The same script is published, with the source
# tarball, at https://github.com/Blckhole-Studio/monolith-ffmpeg
#
# LGPL only: no --enable-gpl, no --enable-nonfree, no external libraries (the build stops if config.h says otherwise).
# Shared libraries (libavcodec.so, libavformat.so, libavutil.so, libswresample.so, libswscale.so), which the app loads at run time, so
# anyone can swap in their own build of the same version. Source: the official FFmpeg 7.1.5 release, unchanged.
#
#   ./build_ffmpeg.sh /path/to/android-ndk        (macOS or Linux; NDK r27c = 27.2.12479018 was used)
#
# Output: out/<abi>/lib*.so (libavcodec, libavformat, libavutil, libswresample, libswscale) and out/include. Inside Monolith's decoder-ffmpeg module they're also copied to
# src/main/jniLibs/<abi> and src/main/cpp/ffmpeg-include.
set -eu
NDK="${1:-${ANDROID_NDK_HOME:-}}"
VERSION="7.1.5"
SHA256="de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f"
API=26   # Monolith's minSdk
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${FFMPEG_WORK:-$HERE/build}"
OUT="$HERE/out"
case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; *) HOST=linux-x86_64 ;; esac
TC="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
[ -d "$TC" ] || { echo "NDK toolchain not found at $TC"; exit 1; }

AUDIO="ac3 eac3 truehd mlp dca flac alac opus vorbis mp3 mp2 mp1 aac pcm_mulaw pcm_alaw pcm_bluray pcm_dvd
  wmav1 wmav2 wmapro cook adpcm_swf nellymoser"
VIDEO="h264 hevc mpeg1video mpeg2video vc1 wmv1 wmv2 wmv3 mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 h263 flv vp6 vp6f vp6a
  vp8 vp9 rv30 rv40"
# Containers Media3 can't read (its own extractors stay first): M2TS/BDAV, MPEG-PS/VOB, ASF/WMV, FLV, RealMedia, AVI.
DEMUXERS="mpegts mpegps asf flv rm avi"
PARSERS="h264 hevc mpegvideo mpeg4video vc1 ac3 dca mlp aac mpegaudio vorbis opus flac"
BSFS="h264_mp4toannexb hevc_mp4toannexb aac_adtstoasc"
DECODERS=""; for d in $AUDIO $VIDEO; do DECODERS="$DECODERS --enable-decoder=$d"; done
for d in $DEMUXERS; do DECODERS="$DECODERS --enable-demuxer=$d"; done
for d in $PARSERS; do DECODERS="$DECODERS --enable-parser=$d"; done
for d in $BSFS; do DECODERS="$DECODERS --enable-bsf=$d"; done

mkdir -p "$WORK"
TARBALL="$WORK/ffmpeg-$VERSION.tar.xz"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
echo "$SHA256  $TARBALL" | shasum -a 256 -c -
SRC="$WORK/ffmpeg-$VERSION"
rm -rf "$SRC"; tar -xJf "$TARBALL" -C "$WORK"
cd "$SRC"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

build() { # abi arch cpu triple extra-cflags
  local abi=$1 arch=$2 cpu=$3 triple=$4 cflags=$5 prefix="$WORK/install/$1"
  make distclean >/dev/null 2>&1 || true
  ./configure --prefix="$prefix" --target-os=android --arch="$arch" --cpu="$cpu" --enable-cross-compile \
    --cc="$TC/${triple}${API}-clang" --cxx="$TC/${triple}${API}-clang++" \
    --nm="$TC/llvm-nm" --ar="$TC/llvm-ar" --ranlib="$TC/llvm-ranlib" --strip="$TC/llvm-strip" \
    --extra-cflags="-O2 -fPIC $cflags" --extra-ldflags="-Wl,-z,max-page-size=16384" \
    --enable-shared --disable-static --disable-symver --enable-pic \
    --disable-doc --disable-programs --disable-everything --disable-network --disable-autodetect \
    --disable-avdevice --disable-avfilter --disable-postproc \
    --enable-avcodec --enable-avformat --enable-avutil --enable-swresample --enable-swscale \
    --disable-v4l2-m2m --disable-vulkan --disable-mediacodec --disable-jni \
    --disable-debug \
    $DECODERS
  grep -q 'CONFIG_GPL 0' config.h && grep -q 'CONFIG_NONFREE 0' config.h || { echo "not an LGPL build"; exit 1; }
  make -j"$JOBS" >/dev/null
  make install >/dev/null
  mkdir -p "$OUT/$abi"
  for l in avutil swresample swscale avcodec avformat; do
    "$TC/llvm-strip" --strip-unneeded -o "$OUT/$abi/lib$l.so" "$prefix/lib/lib$l.so"
  done
  rm -rf "$OUT/include"; cp -R "$prefix/include" "$OUT/include"
  # The exact configure line (the NDK and work folders shortened).
  { echo "FFmpeg $VERSION (LGPL v2.1 or later), built by build_ffmpeg.sh with NDK $(basename "$NDK")"
    grep FFMPEG_CONFIGURATION config.h | sed -e "s#$TC#\$NDK_BIN#g" -e "s#$WORK#\$WORK#g"; } > "$HERE/ffmpeg-configuration-$abi.txt"
  if [ -d "$HERE/src/main" ]; then
    mkdir -p "$HERE/src/main/jniLibs/$abi"; cp "$OUT/$abi/"*.so "$HERE/src/main/jniLibs/$abi/"
    rm -rf "$HERE/src/main/cpp/ffmpeg-include"; cp -R "$OUT/include" "$HERE/src/main/cpp/ffmpeg-include"
  fi
}
build arm64-v8a aarch64 armv8-a aarch64-linux-android ""
build armeabi-v7a arm armv7-a armv7a-linux-androideabi "-march=armv7-a -mfloat-abi=softfp -mfpu=neon"
echo done
