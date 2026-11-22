# monolith-ffmpeg

The FFmpeg build inside **Monolith**, an Android TV media app by Blckhole Studio. Monolith plays most formats with the
TV's own hardware decoders; where a TV can't decode a format (TrueHD, DTS, VC-1, MPEG-2, 10-bit H.264, AV1, ProRes and
others), Monolith decodes it in software with these FFmpeg libraries.

This repository is the source offer for those libraries under the GNU Lesser General Public License, version 2.1
or later. It holds everything needed to rebuild exactly what the app ships.

## What's in the app

- **FFmpeg 7.1.5**, the official release, unmodified. The exact tarball and its SHA-256 are attached to the
  [`n7.1.5-4` release](../../releases/tag/n7.1.5-4) (the build the app ships; `n7.1.5`, `n7.1.5-2` and `n7.1.5-3` were
  earlier builds). It's also at <https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz>.
- **LGPL only.** It's built without `--enable-gpl` or `--enable-nonfree`. The build script stops if FFmpeg's
  `config.h` reports GPL or non-free.
- **Two external libraries:**
  - **dav1d 1.5.1**, VideoLAN's AV1 decoder (BSD 2-clause, [`LICENSE-dav1d`](LICENSE-dav1d)), for AV1 on devices with
    no AV1 hardware decoder. The script downloads the official release from
    <https://downloads.videolan.org/pub/videolan/dav1d/1.5.1/>, checks its SHA-256, builds it with meson and links it
    statically into `libavcodec.so`.
  - **zlib**, Android's own (`libz.so`, part of the NDK and every device), for compressed QuickTime headers and
    Sorenson Video 3.
- **Shared libraries**, loaded by the app at run time: `libavcodec.so`, `libavformat.so`, `libavfilter.so`,
  `libavutil.so`, `libswresample.so` and `libswscale.so`, in the APK's `lib/<abi>/` folder. You can replace them with
  your own build of the same version.
- **ABIs:** `arm64-v8a` and `armeabi-v7a` (with NEON). The API level is 26 (Android 8.0), the app's minimum.
- **NDK:** r27c (27.2.12479018), on macOS.
- **Decoders**, **demuxers**, **parsers** and **bitstream filters:** the lists at the top of
  [`build_ffmpeg.sh`](build_ffmpeg.sh). In short: the Dolby, DTS and lossless audio codecs, WMA, RealAudio, ATRAC,
  ADPCM, Monkey's Audio, WavPack, TTA, DSD and PCM; H.264, HEVC, MPEG-1/2/4, VC-1, WMV, VP6 to VP9, AV1 (dav1d),
  RealVideo, ProRes, DNxHD, Theora, Sorenson, Indeo, Cinepak, MJPEG, DV, FFV1 and other lossless codecs; and the
  containers the app's own readers can't open (M2TS/BDAV, VOB, ASF, FLV, RealMedia, AVI, Matroska and MOV for codecs
  the app's readers drop, Ogg, APE, WavPack, TTA, DSF, DFF, AIFF and WAV).
- **One filter graph:** bwdif (with buffer, buffersink and format), to deinterlace the video it decodes.
- **One encoder:** AC-3 (Dolby Digital), to send multichannel sound to a TV or soundbar that takes AC-3 over HDMI/ARC
  but not multichannel PCM.
- Everything else is disabled: no other encoders, no avdevice, network, protocols, programs or autodetected libraries.

The exact `configure` lines are in [`ffmpeg-configuration-arm64-v8a.txt`](ffmpeg-configuration-arm64-v8a.txt) and
[`ffmpeg-configuration-armeabi-v7a.txt`](ffmpeg-configuration-armeabi-v7a.txt). In them, `$NDK_BIN` is the NDK's
`toolchains/llvm/prebuilt/<host>/bin` and `$WORK` is the build folder.

## Rebuild it

You need the Android NDK, `make`, `curl`, `shasum`, `meson`, `ninja` and `pkg-config` on macOS or Linux.

```sh
./build_ffmpeg.sh /path/to/android-ndk
```

The script downloads the tarball and checks its SHA-256. It then builds both ABIs, strips the libraries and writes
them to `out/<abi>/` with the headers in `out/include/`.

## Licence

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later. The full text is in
[`LICENSE`](LICENSE). The build script in this repository is under the same licence. dav1d is under the BSD 2-clause
licence, in [`LICENSE-dav1d`](LICENSE-dav1d).
