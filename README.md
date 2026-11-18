# monolith-ffmpeg

The FFmpeg build inside **Monolith**, an Android TV media app by Blckhole Studio. Monolith plays most formats with the
TV's own hardware decoders; where a TV can't decode a format (TrueHD, DTS, VC-1, MPEG-2, 10-bit H.264 and others),
Monolith decodes it in software with these FFmpeg libraries.

This repository is the source offer for those libraries under the GNU Lesser General Public License, version 2.1
or later. It holds everything needed to rebuild exactly what the app ships.

## What's in the app

- **FFmpeg 7.1.5**, the official release, unmodified. The exact tarball and its SHA-256 are attached to the
  [`n7.1.5` release](../../releases/tag/n7.1.5). It's also at <https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz>.
- **LGPL only.** It's built without `--enable-gpl`, `--enable-nonfree` or any external library. The build script
  stops if FFmpeg's `config.h` reports GPL or non-free.
- **Shared libraries**, loaded by the app at run time: `libavcodec.so`, `libavformat.so`, `libavutil.so`,
  `libswresample.so` and `libswscale.so`, in the APK's `lib/<abi>/` folder. You can replace them with your own build of the same version.
- **ABIs:** `arm64-v8a` and `armeabi-v7a` (with NEON). The API level is 26 (Android 8.0), the app's minimum.
- **NDK:** r27c (27.2.12479018), on macOS.
- **Decoders:**
  - Audio: ac3, eac3, truehd, mlp, dca, flac, alac, opus, vorbis, mp1, mp2, mp3, aac, pcm_mulaw, pcm_alaw,
    pcm_bluray, pcm_dvd, wmav1, wmav2, wmapro, cook, adpcm_swf and nellymoser.
  - Video: h264, hevc, mpeg1video, mpeg2video, vc1, wmv1, wmv2, wmv3, mpeg4, msmpeg4v1-3, h263, flv, vp6, vp6f,
    vp6a, vp8, vp9, rv30 and rv40.
- **Demuxers** (containers the app's own readers can't open): mpegts (M2TS/BDAV), mpegps (VOB), asf, flv, rm and avi,
  with the parsers and bitstream filters listed in the build script.
- Everything else is disabled: no avfilter, avdevice, network, protocols, programs or autodetected libraries.

The exact `configure` lines are in [`ffmpeg-configuration-arm64-v8a.txt`](ffmpeg-configuration-arm64-v8a.txt) and
[`ffmpeg-configuration-armeabi-v7a.txt`](ffmpeg-configuration-armeabi-v7a.txt). In them, `$NDK_BIN` is the NDK's
`toolchains/llvm/prebuilt/<host>/bin` and `$WORK` is the build folder.

## Rebuild it

You need the Android NDK, `make`, `curl` and `shasum` on macOS or Linux.

```sh
./build_ffmpeg.sh /path/to/android-ndk
```

The script downloads the tarball and checks its SHA-256. It then builds both ABIs, strips the libraries and writes
them to `out/<abi>/` with the headers in `out/include/`.

## Licence

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later. The full text is in
[`LICENSE`](LICENSE). The build script in this repository is under the same licence.
