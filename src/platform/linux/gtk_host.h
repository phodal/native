#ifndef NATIVE_SDK_GTK_HOST_H
#define NATIVE_SDK_GTK_HOST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct native_sdk_gtk_host native_sdk_gtk_host_t;

typedef enum {
    NATIVE_SDK_GTK_EVENT_START = 0,
    NATIVE_SDK_GTK_EVENT_FRAME = 1,
    NATIVE_SDK_GTK_EVENT_SHUTDOWN = 2,
    NATIVE_SDK_GTK_EVENT_RESIZE = 3,
    NATIVE_SDK_GTK_EVENT_WINDOW_FRAME = 4,
    NATIVE_SDK_GTK_EVENT_SHORTCUT = 5,
    NATIVE_SDK_GTK_EVENT_NATIVE_COMMAND = 6,
    NATIVE_SDK_GTK_EVENT_APP_ACTIVATED = 7,
    NATIVE_SDK_GTK_EVENT_APP_DEACTIVATED = 8,
    NATIVE_SDK_GTK_EVENT_MENU_COMMAND = 9,
    NATIVE_SDK_GTK_EVENT_FILES_DROPPED = 10,
    NATIVE_SDK_GTK_EVENT_GPU_SURFACE_FRAME = 11,
    NATIVE_SDK_GTK_EVENT_GPU_SURFACE_RESIZE = 12,
    NATIVE_SDK_GTK_EVENT_GPU_SURFACE_INPUT = 13,
    NATIVE_SDK_GTK_EVENT_WAKE = 14,
    NATIVE_SDK_GTK_EVENT_TIMER = 15,
    NATIVE_SDK_GTK_EVENT_APPEARANCE = 16,
} native_sdk_gtk_event_kind_t;

typedef struct {
    native_sdk_gtk_event_kind_t kind;
    uint64_t window_id;
    double width;
    double height;
    double scale;
    double x;
    double y;
    int open;
    int focused;
    const char *label;
    size_t label_len;
    const char *title;
    size_t title_len;
    const char *shortcut_id;
    size_t shortcut_id_len;
    const char *shortcut_key;
    size_t shortcut_key_len;
    uint32_t shortcut_modifiers;
    const char *command_name;
    size_t command_name_len;
    const char *view_label;
    size_t view_label_len;
    const char *drop_paths;
    size_t drop_paths_len;
    uint64_t frame_index;
    uint64_t timestamp_ns;
    uint64_t frame_interval_ns;
    int nonblank;
    uint32_t sample_color;
    int input_kind;
    int button;
    double delta_x;
    double delta_y;
    const char *key_text;
    size_t key_text_len;
    const char *input_text;
    size_t input_text_len;
    int has_composition_cursor;
    size_t composition_cursor;
    uint64_t timer_id;
    /* Appearance events: 0 = light, 1 = dark. */
    int color_scheme;
    int reduce_motion;
    int high_contrast;
} native_sdk_gtk_event_t;

typedef void (*native_sdk_gtk_event_callback_t)(void *context, const native_sdk_gtk_event_t *event);
typedef void (*native_sdk_gtk_bridge_callback_t)(void *context, uint64_t window_id, const char *webview_label, size_t webview_label_len, const char *message, size_t message_len, const char *origin, size_t origin_len);

typedef struct {
    const char *title;
    size_t title_len;
    const char *default_path;
    size_t default_path_len;
    const char *extensions;
    size_t extensions_len;
    int allow_directories;
    int allow_multiple;
} native_sdk_gtk_open_dialog_opts_t;

typedef struct {
    size_t count;
    size_t bytes_written;
} native_sdk_gtk_open_dialog_result_t;

typedef struct {
    const char *title;
    size_t title_len;
    const char *default_path;
    size_t default_path_len;
    const char *default_name;
    size_t default_name_len;
    const char *extensions;
    size_t extensions_len;
} native_sdk_gtk_save_dialog_opts_t;

typedef struct {
    int style;
    const char *title;
    size_t title_len;
    const char *message;
    size_t message_len;
    const char *informative_text;
    size_t informative_text_len;
    const char *primary_button;
    size_t primary_button_len;
    const char *secondary_button;
    size_t secondary_button_len;
    const char *tertiary_button;
    size_t tertiary_button_len;
} native_sdk_gtk_message_dialog_opts_t;

/* resizable/titlebar_style/min_width/min_height mirror the AppKit host's
 * window options: titlebar_style 0 = standard decorations, >= 1 = the
 * hidden styles (the app draws its own chrome, so the window is created
 * undecorated); min_width/min_height <= 0 leave that axis unfloored. */
native_sdk_gtk_host_t *native_sdk_gtk_create(const char *app_name, size_t app_name_len, const char *window_title, size_t window_title_len, const char *bundle_id, size_t bundle_id_len, const char *icon_path, size_t icon_path_len, const char *window_label, size_t window_label_len, double x, double y, double width, double height, int restore_frame, int resizable, int titlebar_style, double min_width, double min_height);
void native_sdk_gtk_destroy(native_sdk_gtk_host_t *host);
void native_sdk_gtk_run(native_sdk_gtk_host_t *host, native_sdk_gtk_event_callback_t callback, void *context);
void native_sdk_gtk_stop(native_sdk_gtk_host_t *host);
/* Thread-safe: schedules a WAKE event on the GLib main loop via
 * g_idle_add. May be called from any thread (effect worker threads). */
void native_sdk_gtk_wake(native_sdk_gtk_host_t *host);
/* Decode encoded image bytes (PNG, JPEG, ... — whatever gdk-pixbuf
 * loaders are installed) into tightly packed, row-major, straight-alpha
 * RGBA8 written into `pixels`. Returns 1 on success (with `out_width`/
 * `out_height` set), 0 when the bytes cannot be decoded, and -1 when the
 * decoded pixels do not fit `pixels_len` (`out_width`/`out_height` still
 * report the decoded dimensions). */
int native_sdk_gtk_decode_image(const uint8_t *bytes, size_t bytes_len, uint8_t *pixels, size_t pixels_len, size_t *out_width, size_t *out_height);
void native_sdk_gtk_load_webview(native_sdk_gtk_host_t *host, const char *source, size_t source_len, int source_kind, const char *asset_root, size_t asset_root_len, const char *asset_entry, size_t asset_entry_len, const char *asset_origin, size_t asset_origin_len, int spa_fallback);
void native_sdk_gtk_load_window_webview(native_sdk_gtk_host_t *host, uint64_t window_id, const char *source, size_t source_len, int source_kind, const char *asset_root, size_t asset_root_len, const char *asset_entry, size_t asset_entry_len, const char *asset_origin, size_t asset_origin_len, int spa_fallback);
void native_sdk_gtk_set_bridge_callback(native_sdk_gtk_host_t *host, native_sdk_gtk_bridge_callback_t callback, void *context);
void native_sdk_gtk_bridge_respond(native_sdk_gtk_host_t *host, const char *response, size_t response_len);
void native_sdk_gtk_bridge_respond_window(native_sdk_gtk_host_t *host, uint64_t window_id, const char *response, size_t response_len);
void native_sdk_gtk_bridge_respond_webview(native_sdk_gtk_host_t *host, uint64_t window_id, const char *webview_label, size_t webview_label_len, const char *response, size_t response_len);
void native_sdk_gtk_emit_window_event(native_sdk_gtk_host_t *host, uint64_t window_id, const char *name, size_t name_len, const char *detail_json, size_t detail_json_len);
void native_sdk_gtk_set_security_policy(native_sdk_gtk_host_t *host, const char *allowed_origins, size_t allowed_origins_len, const char *external_urls, size_t external_urls_len, int external_action);
void native_sdk_gtk_set_menus(native_sdk_gtk_host_t *host, const char *const *menu_titles, const size_t *menu_title_lens, size_t menu_count, const uint32_t *item_menu_indices, const char *const *item_labels, const size_t *item_label_lens, const char *const *item_commands, const size_t *item_command_lens, const char *const *item_keys, const size_t *item_key_lens, const uint32_t *item_modifiers, const int *item_separators, const int *item_enabled, const int *item_checked, size_t item_count);
void native_sdk_gtk_set_shortcuts(native_sdk_gtk_host_t *host, const char *const *ids, const size_t *id_lens, const char *const *keys, const size_t *key_lens, const uint32_t *modifiers, size_t count);
int native_sdk_gtk_create_window(native_sdk_gtk_host_t *host, uint64_t window_id, const char *window_title, size_t window_title_len, const char *window_label, size_t window_label_len, double x, double y, double width, double height, int restore_frame, int resizable, int titlebar_style, double min_width, double min_height);
/* Ask the windowing system to start an interactive move from the last
 * pointer press (the widget `window_drag` channel). Returns 0 when the
 * window is unknown or no press has been recorded yet. */
int native_sdk_gtk_start_window_drag(native_sdk_gtk_host_t *host, uint64_t window_id);
/* App timers on the GLib main loop: starting an id that is already
 * scheduled replaces it; a non-repeating timer drops its slot before
 * emitting so the handler may re-arm the same id. */
void native_sdk_gtk_start_timer(native_sdk_gtk_host_t *host, uint64_t timer_id, uint64_t interval_ns, int repeats);
void native_sdk_gtk_cancel_timer(native_sdk_gtk_host_t *host, uint64_t timer_id);
int native_sdk_gtk_focus_window(native_sdk_gtk_host_t *host, uint64_t window_id);
int native_sdk_gtk_close_window(native_sdk_gtk_host_t *host, uint64_t window_id);
int native_sdk_gtk_create_view(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, int kind, const char *parent, size_t parent_len, double x, double y, double width, double height, int layer, int visible, int enabled, const char *role, size_t role_len, const char *accessibility_label, size_t accessibility_label_len, const char *text, size_t text_len, const char *command, size_t command_len);
int native_sdk_gtk_update_view(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, int has_frame, double x, double y, double width, double height, int has_layer, int layer, int has_visible, int visible, int has_enabled, int enabled, int has_role, const char *role, size_t role_len, int has_accessibility_label, const char *accessibility_label, size_t accessibility_label_len, int has_text, const char *text, size_t text_len, int has_command, const char *command, size_t command_len);
int native_sdk_gtk_set_view_frame(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, double x, double y, double width, double height);
int native_sdk_gtk_set_view_visible(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, int visible);
int native_sdk_gtk_focus_view(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len);
int native_sdk_gtk_close_view(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len);
int native_sdk_gtk_request_gpu_surface_frame(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len);
int native_sdk_gtk_present_gpu_surface_pixels(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, size_t width, size_t height, double scale, int has_dirty_rect, double dirty_x, double dirty_y, double dirty_width, double dirty_height, const uint8_t *rgba8, size_t rgba8_len);
int native_sdk_gtk_create_webview(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, const char *url, size_t url_len, double x, double y, double width, double height, int layer, int transparent, int bridge_enabled);
int native_sdk_gtk_set_webview_frame(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, double x, double y, double width, double height);
int native_sdk_gtk_navigate_webview(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, const char *url, size_t url_len);
int native_sdk_gtk_set_webview_zoom(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, double zoom);
int native_sdk_gtk_set_webview_layer(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len, int layer);
int native_sdk_gtk_close_webview(native_sdk_gtk_host_t *host, uint64_t window_id, const char *label, size_t label_len);
int native_sdk_gtk_open_external_url(native_sdk_gtk_host_t *host, const char *url, size_t url_len);
int native_sdk_gtk_reveal_path(native_sdk_gtk_host_t *host, const char *path, size_t path_len);
int native_sdk_gtk_show_notification(native_sdk_gtk_host_t *host, const char *title, size_t title_len, const char *subtitle, size_t subtitle_len, const char *body, size_t body_len);
int native_sdk_gtk_add_recent_document(native_sdk_gtk_host_t *host, const char *path, size_t path_len);
int native_sdk_gtk_clear_recent_documents(native_sdk_gtk_host_t *host);
int native_sdk_gtk_credentials_available(native_sdk_gtk_host_t *host);
int native_sdk_gtk_set_credential(native_sdk_gtk_host_t *host, const char *service, size_t service_len, const char *account, size_t account_len, const char *secret, size_t secret_len);
size_t native_sdk_gtk_get_credential(native_sdk_gtk_host_t *host, const char *service, size_t service_len, const char *account, size_t account_len, char *buffer, size_t buffer_len);
int native_sdk_gtk_delete_credential(native_sdk_gtk_host_t *host, const char *service, size_t service_len, const char *account, size_t account_len);
size_t native_sdk_gtk_clipboard_read(native_sdk_gtk_host_t *host, char *buffer, size_t buffer_len);
void native_sdk_gtk_clipboard_write(native_sdk_gtk_host_t *host, const char *text, size_t text_len);
size_t native_sdk_gtk_clipboard_read_data(native_sdk_gtk_host_t *host, const char *mime_type, size_t mime_type_len, char *buffer, size_t buffer_len);
int native_sdk_gtk_clipboard_write_data(native_sdk_gtk_host_t *host, const char *mime_type, size_t mime_type_len, const char *bytes, size_t bytes_len);
native_sdk_gtk_open_dialog_result_t native_sdk_gtk_show_open_dialog(native_sdk_gtk_host_t *host, const native_sdk_gtk_open_dialog_opts_t *opts, char *buffer, size_t buffer_len);
size_t native_sdk_gtk_show_save_dialog(native_sdk_gtk_host_t *host, const native_sdk_gtk_save_dialog_opts_t *opts, char *buffer, size_t buffer_len);
int native_sdk_gtk_show_message_dialog(native_sdk_gtk_host_t *host, const native_sdk_gtk_message_dialog_opts_t *opts);

#ifdef __cplusplus
}
#endif

#endif
