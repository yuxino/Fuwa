#ifndef FUWA_MYGO_BRIDGE_H
#define FUWA_MYGO_BRIDGE_H
#include <stdint.h>
// All entry points run on MyGo's main thread. Returned strings are malloc-owned.
void fw_initialize(void);
char *fw_inventory(void);
char *fw_events(void);
int fw_screen_allowed(void);
int fw_request_screen(void);
int fw_ax_allowed(void);
void fw_management_active(uintptr_t host, int active);
void fw_start(uint64_t token, uint64_t generation, uint32_t window_id,
              int32_t pid, double birth, uintptr_t host);
// Call after the Go-owned host has been shown for this generation. Native
// presentation waits another main-loop turn plus a subsequent complete frame.
void fw_presented(uint64_t token, uint64_t generation);
char *fw_freeze(uint64_t token);
void fw_stop(uint64_t token);
void fw_resize(uint64_t token, double width, double height, double scale);
char *fw_reveal(uint32_t window_id, int32_t pid, double birth);
int fw_login_state(void);
char *fw_set_login(int enabled);
#ifdef FUWA_PARITY_QA
// Own-buffer regression tests. This entry never creates an SCStream or asks TCC.
char *fw_qa_capture_lifecycle(void);
#endif
#endif
