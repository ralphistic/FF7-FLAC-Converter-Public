# Decoder integration checkpoint (2026-11-18)

## Verified
- iOS shell builds unsigned IPA via GitHub Actions.
- File importer parses PSF1 tags and reports missing _lib references.
- CI metadata fixture originally failed because the Swift string contained literal backslash-n characters. Fixed in commit c831c165; verify new run.
- OpenPSF (myst6re/openpsf) has a C interface: initialize core, create, open, decode up to 1024 samples per call, close, destroy. It is **not a standalone drop-in**: openpsf.cpp includes ../highly_experimental/Core/*.h and psflib.h/psf2fs.h. Its initialization also takes a BIOS path. Do not assume it works on iOS or that a distributable BIOS can be bundled.

## Critical requirements
- Decode complete PSF1/miniPSF audio with correct _lib dependency resolution and sample-accurate duration + fade. No fixed 180-second cutoff.
- Export 44.1 kHz stereo 16-bit FLAC with actual decoded PCM, not a renamed file or silence.
- Select multiple tracks and library files through Files, export all files on device.
- Validate output durations, non-silence, and errors before reporting success.
- Unsigned IPA must be signable with Signulous.

## Next implementation path
1. Choose an iOS-buildable PSF1 decoder with compatible redistributable source and dependencies; verify license, architecture, external BIOS requirements, and library resolution before integration. OpenPSF is a candidate, not yet confirmed.
2. Vendor source and dependencies or fetch pinned commits in CI, compile for iphoneos arm64, and expose a minimal C bridge to Swift.
3. Integrate an iOS-buildable FLAC encoder (libFLAC or equivalent) and write a full-length PCM-to-FLAC conversion pipeline with cancellation and progress.
4. Obtain or generate a legally redistributable PSF1 test fixture and CI-decode it, verify frame count, non-silence, FLAC integrity and end-to-end duration.
5. Test One-Winged Angel with user-provided source assets; its metadata length=6:53 fade=10 means expected 7:03 if fade is additional, subject to decoder semantics.
6. Only then provide IPA installation instructions.

## Known failed approaches
- iSH psf2wav -d is not a supported option; psf2wav -h is also unsupported.
- iSH full-length decoding was too slow or stalled; prior batch used -t 180, truncating songs.
- iSH Safari localhost transfer of a ~105 MB zip repeatedly failed/broke pipe.
- Earlier CI regression fixture used \\n instead of actual newline escapes, causing a precondition failure.
