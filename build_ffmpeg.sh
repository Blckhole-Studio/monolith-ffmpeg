#!/bin/bash
# Builds the FFmpeg libraries that Monolith's software decoders use. The same script is published, with the source
# tarball, at https://github.com/Blckhole-Studio/monolith-ffmpeg
#
# LGPL only: no --enable-gpl, no --enable-nonfree (the build stops if config.h says otherwise). One external library:
# dav1d (BSD 2-clause, VideoLAN's AV1 decoder), built here from its official release and linked statically into
# libavcodec, for AV1 on devices with no AV1 hardware decoder. zlib is Android's own (libz.so, part of the NDK):
# compressed QuickTime headers, watermarked Sorenson Video 3.
# Shared libraries (libavcodec.so, libavformat.so, libavfilter.so, libavutil.so, libswresample.so, libswscale.so), which the app loads at run time, so
# anyone can swap in their own build of the same version. Source: the official FFmpeg 7.1.5 release, unchanged.
#
#   ./build_ffmpeg.sh /path/to/android-ndk        (macOS or Linux; NDK r27c = 27.2.12479018 was used)
#
# Output: out/<abi>/lib*.so (libavcodec with dav1d inside, libavformat, libavfilter, libavutil, libswresample, libswscale) and out/include. Inside Monolith's decoder-ffmpeg module they're also copied to
# src/main/jniLibs/<abi> and src/main/cpp/ffmpeg-include.
set -eu
NDK="${1:-${ANDROID_NDK_HOME:-}}"
VERSION="7.1.5"
SHA256="de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f"
DAV1D_VERSION="1.5.1"
DAV1D_SHA256="401813f1f89fa8fd4295805aa5284d9aed9bc7fc1fdbe554af4292f64cbabe21"
MESON="${MESON:-meson}"   # dav1d builds with meson and ninja
API=26   # Monolith's minSdk
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${FFMPEG_WORK:-$HERE/build}"
OUT="$HERE/out"
case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; *) HOST=linux-x86_64 ;; esac
TC="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
[ -d "$TC" ] || { echo "NDK toolchain not found at $TC"; exit 1; }

AUDIO="ac3 eac3 truehd mlp dca flac alac opus vorbis mp3 mp2 mp1 aac pcm_mulaw pcm_alaw pcm_bluray pcm_dvd
  wmav1 wmav2 wmapro wmalossless wmavoice cook sipr ra_144 ra_288 ralf atrac3 atrac3p atrac9 adpcm_swf adpcm_ms
  adpcm_ima_wav adpcm_ima_qt nellymoser amrnb amrwb gsm gsm_ms qdm2 qdmc ape wavpack tta mace3 mace6 truespeech imc
  dsd_lsbf dsd_msbf dsd_lsbf_planar dsd_msbf_planar pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_s32be pcm_f32le
  pcm_f32be pcm_u8 pcm_s8"
VIDEO="h264 hevc mpeg1video mpeg2video vc1 wmv1 wmv2 wmv3 mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 h263 h263p h261 flv vp6
  vp6f vp6a vp7 vp8 vp9 rv10 rv20 rv30 rv40 libdav1d prores dnxhd theora vp3 svq1 svq3 indeo2 indeo3 indeo4 indeo5
  cinepak mjpeg mjpegb dvvideo qtrle rpza smc msvideo1 huffyuv ffvhuff ffv1 utvideo rawvideo 8bps"
# Containers Media3 can't read (its own extractors stay first): M2TS/BDAV, MPEG-PS/VOB, ASF/WMV, FLV, RealMedia, AVI;
# and for codecs Media3's own readers drop: Matroska and MOV/MP4 (ProRes, DNxHD, Theora, RealVideo in MKV…), Ogg
# (Theora), and audio-only formats (Monkey's Audio, WavPack, TTA, DSD, AIFF, WAV with ADPCM/GSM…).
DEMUXERS="mpegts mpegps asf flv rm avi matroska mov ogg ape wv tta dsf iff aiff wav"
PARSERS="h264 hevc mpegvideo mpeg4video vc1 ac3 dca mlp aac mpegaudio vorbis opus flac rv34 vp3 dvdsub gsm"
# Deinterlacing for interlaced video FFmpeg decodes (MPEG-2, VC-1, H.264 1080i): bwdif, as most players use.
FILTERS="bwdif buffer buffersink format"
BSFS="h264_mp4toannexb hevc_mp4toannexb aac_adtstoasc"
DECODERS=""; for d in $AUDIO $VIDEO; do DECODERS="$DECODERS --enable-decoder=$d"; done
for d in $DEMUXERS; do DECODERS="$DECODERS --enable-demuxer=$d"; done
for d in $PARSERS; do DECODERS="$DECODERS --enable-parser=$d"; done
for d in $BSFS; do DECODERS="$DECODERS --enable-bsf=$d"; done
for d in $FILTERS; do DECODERS="$DECODERS --enable-filter=$d"; done

mkdir -p "$WORK"
TARBALL="$WORK/ffmpeg-$VERSION.tar.xz"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
echo "$SHA256  $TARBALL" | shasum -a 256 -c -
SRC="$WORK/ffmpeg-$VERSION"
rm -rf "$SRC"; tar -xJf "$TARBALL" -C "$WORK"
cd "$SRC"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

DAV1D_TARBALL="$WORK/dav1d-$DAV1D_VERSION.tar.xz"
[ -f "$DAV1D_TARBALL" ] || curl -fsSL -o "$DAV1D_TARBALL" "https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz"
echo "$DAV1D_SHA256  $DAV1D_TARBALL" | shasum -a 256 -c -
rm -rf "$WORK/dav1d-$DAV1D_VERSION"; tar -xJf "$DAV1D_TARBALL" -C "$WORK"

dav1d() { # abi cpu-family cpu triple: a static libdav1d.a and its pkg-config file under $WORK/install/<abi>
  local abi=$1 family=$2 cpu=$3 triple=$4 prefix="$WORK/install/$1" cross="$WORK/dav1d-$1.cross"
  cat > "$cross" <<CROSS
[binaries]
c = '$TC/${triple}${API}-clang'
cpp = '$TC/${triple}${API}-clang++'
ar = '$TC/llvm-ar'
strip = '$TC/llvm-strip'
[host_machine]
system = 'android'
cpu_family = '$family'
cpu = '$cpu'
endian = 'little'
CROSS
  rm -rf "$WORK/dav1d-build-$abi"
  (cd "$WORK/dav1d-$DAV1D_VERSION" && "$MESON" setup "$WORK/dav1d-build-$abi" --cross-file "$cross" --prefix "$prefix" \
    --libdir lib --buildtype release --default-library static -Denable_tools=false -Denable_tests=false \
    -Denable_examples=false -Dc_args="-fPIC" >/dev/null)
  ninja -C "$WORK/dav1d-build-$abi" install >/dev/null
}

build() { # abi arch cpu triple extra-cflags
  local abi=$1 arch=$2 cpu=$3 triple=$4 cflags=$5 prefix="$WORK/install/$1"
  make distclean >/dev/null 2>&1 || true
  PKG_CONFIG_PATH="$prefix/lib/pkgconfig" PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" ./configure --prefix="$prefix" --target-os=android --arch="$arch" --cpu="$cpu" --enable-cross-compile \
    --cc="$TC/${triple}${API}-clang" --cxx="$TC/${triple}${API}-clang++" \
    --nm="$TC/llvm-nm" --ar="$TC/llvm-ar" --ranlib="$TC/llvm-ranlib" --strip="$TC/llvm-strip" \
    --extra-cflags="-O2 -fPIC $cflags" --extra-ldflags="-Wl,-z,max-page-size=16384" \
    --enable-shared --disable-static --disable-symver --enable-pic \
    --disable-doc --disable-programs --disable-everything --disable-network --disable-autodetect \
    --disable-avdevice --disable-postproc --pkg-config=pkg-config --enable-libdav1d --enable-zlib \
    --enable-avcodec --enable-avformat --enable-avutil --enable-swresample --enable-swscale --enable-avfilter \
    --disable-v4l2-m2m --disable-vulkan --disable-mediacodec --disable-jni \
    --disable-debug \
    $DECODERS
  grep -q 'CONFIG_GPL 0' config.h && grep -q 'CONFIG_NONFREE 0' config.h || { echo "not an LGPL build"; exit 1; }
  make -j"$JOBS" >/dev/null
  make install >/dev/null
  mkdir -p "$OUT/$abi"
  for l in avutil swresample swscale avcodec avformat avfilter; do
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
dav1d arm64-v8a aarch64 armv8-a aarch64-linux-android
build arm64-v8a aarch64 armv8-a aarch64-linux-android ""
dav1d armeabi-v7a arm armv7-a armv7a-linux-androideabi
build armeabi-v7a arm armv7-a armv7a-linux-androideabi "-march=armv7-a -mfloat-abi=softfp -mfpu=neon"
echo done
