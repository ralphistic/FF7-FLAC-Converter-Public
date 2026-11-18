#ifndef FF7_PSF_DECODER_BRIDGE_H
#define FF7_PSF_DECODER_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*ff7_pcm_callback)(const uint8_t *bytes, long byte_count, void *context);
/// Returns 0 if decoding completed, -1 if loading failed.
/// The decoder uses process-global state; never call concurrently.
int ff7_decode_psf(const char *path, ff7_pcm_callback callback, void *context);
/// Request the currently active decode to end on the next SPU cycle.
void ff7_stop_psf(void);
#ifdef __cplusplus
}
#endif
#endif
