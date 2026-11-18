#include "PSFDecoderBridge.h"
#include "Vendor/sexypsf/driver.h"
#include <stddef.h>

static ff7_pcm_callback current_callback = NULL;
static void *current_context = NULL;

void sexyd_update(unsigned char *bytes, long count) {
    if (bytes && count > 0 && current_callback) {
        current_callback(bytes, count, current_context);
    }
}

void ff7_stop_psf(void) {
    if (current_callback) sexy_stop();
}

int ff7_decode_psf(const char *path, ff7_pcm_callback callback, void *context) {
    if (!path || !callback || current_callback) return -1;
    current_callback = callback;
    current_context = context;
    PSFINFO *info = sexy_load((char *)path);
    if (!info) {
        current_callback = NULL;
        current_context = NULL;
        return -1;
    }
    sexy_execute();
    sexy_freepsfinfo(info);
    current_callback = NULL;
    current_context = NULL;
    return 0;
}
