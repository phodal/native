#include <windows.h>
#include <shellapi.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#if !__has_include(<WebView2.h>)
#error "WebView2.h is required for the Windows system WebView backend. Install the Microsoft WebView2 SDK headers."
#else
#include <WebView2.h>
#include <wrl.h>
#endif

#include "../bridge_script.h"

#if __has_include(<WebView2.h>)

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

enum EventKind {
    kStart = 0,
    kFrame = 1,
    kShutdown = 2,
    kResize = 3,
    kWindowFrame = 4,
};

enum ResourceResult {
    kResourceInvalidArgument = 0,
    kResourceOk = 1,
    kResourceLimit = 2,
    kResourceOutOfMemory = 3,
};

enum ResourceCloseReason {
    kResourceComplete = 0,
    kResourceCancel = 1,
    kResourceRevoke = 2,
    kResourceExpired = 3,
    kResourceFailure = 4,
};

static const size_t kMaxDynamicResources = 128;

struct WindowsEvent {
    int kind;
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
};

using EventCallback = void (*)(void *, const WindowsEvent *);
using BridgeCallback = void (*)(void *, uint64_t, const char *, size_t, const char *, size_t);
using ResourceStreamReadCallback = intptr_t (*)(void *, const char *, size_t, const char *, size_t, uint64_t, char *, size_t);
using ResourceStreamCloseCallback = void (*)(void *, const char *, size_t, int);
using CreateCoreWebView2EnvironmentWithOptionsFn = HRESULT(STDMETHODCALLTYPE *)(PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);

struct DynamicResource {
    std::string id;
    std::string mime;
    std::string origin;
    uint64_t window_id = 0;
    int64_t expires_at_ns = 0;
    bool has_expiry = false;
    bool one_shot = true;
    bool streaming = false;
    std::vector<uint8_t> bytes;
    uint64_t size = 0;
    bool has_size = false;
    void *stream_context = nullptr;
    ResourceStreamReadCallback read_callback = nullptr;
    ResourceStreamCloseCallback close_callback = nullptr;
    std::mutex stream_mutex;
    bool closed = false;
    bool eof = false;
    bool failed = false;
};

struct Window {
    uint64_t id = 1;
    HWND hwnd = nullptr;
    std::string label;
    std::string title;
    double x = 0;
    double y = 0;
    double width = 720;
    double height = 480;
    std::string source;
    int source_kind = 0;
    std::string asset_root;
    std::string asset_entry;
    std::string asset_origin;
    int spa_fallback = 1;
    std::string current_origin = "zero://inline";
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> webview;
    EventRegistrationToken message_token = {};
    EventRegistrationToken source_token = {};
    EventRegistrationToken resource_token = {};
};

struct Host {
    HINSTANCE instance = GetModuleHandleW(nullptr);
    std::string app_name;
    std::string window_title;
    std::string bundle_id;
    std::string icon_path;
    EventCallback callback = nullptr;
    void *callback_context = nullptr;
    BridgeCallback bridge_callback = nullptr;
    void *bridge_context = nullptr;
    bool running = false;
    HMODULE webview2_loader = nullptr;
    CreateCoreWebView2EnvironmentWithOptionsFn create_environment = nullptr;
    bool environment_requested = false;
    ComPtr<ICoreWebView2Environment> environment;
    std::map<uint64_t, Window> windows;
    std::mutex resource_mutex;
    std::map<std::string, std::shared_ptr<DynamicResource>> resources;
};

static std::string slice(const char *bytes, size_t len) {
    return bytes && len > 0 ? std::string(bytes, len) : std::string();
}

static std::wstring widen(const std::string &value) {
    if (value.empty()) return std::wstring();
    int count = MultiByteToWideChar(CP_UTF8, 0, value.data(), (int)value.size(), nullptr, 0);
    if (count <= 0) return std::wstring();
    std::wstring out((size_t)count, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), (int)value.size(), out.data(), count);
    return out;
}

static std::string narrow(const wchar_t *value) {
    if (!value) return std::string();
    int len = lstrlenW(value);
    if (len <= 0) return std::string();
    int count = WideCharToMultiByte(CP_UTF8, 0, value, len, nullptr, 0, nullptr, nullptr);
    if (count <= 0) return std::string();
    std::string out((size_t)count, '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, len, out.data(), count, nullptr, nullptr);
    return out;
}

static size_t boundedLen(const char *text, size_t limit) {
    size_t len = 0;
    while (len < limit && text[len] != '\0') ++len;
    return len;
}

static int64_t nowNanoseconds() {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER ticks;
    ticks.LowPart = ft.dwLowDateTime;
    ticks.HighPart = ft.dwHighDateTime;
    const uint64_t unix_epoch_ticks = 116444736000000000ULL;
    if (ticks.QuadPart <= unix_epoch_ticks) return 0;
    return (int64_t)((ticks.QuadPart - unix_epoch_ticks) * 100);
}

static std::string lowerAscii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return (char)std::tolower(ch);
    });
    return value;
}

static std::string originForUrl(const std::string &url) {
    if (url.empty()) return "zero://inline";
    size_t colon = url.find(':');
    if (colon == std::string::npos) return "zero://inline";
    std::string scheme = lowerAscii(url.substr(0, colon));
    if (scheme.empty() || scheme == "about") return "zero://inline";
    if (scheme == "file") return "file://local";
    size_t authority_start = colon + 1;
    if (url.compare(authority_start, 2, "//") == 0) authority_start += 2;
    size_t authority_end = url.find_first_of("/?#", authority_start);
    std::string authority = url.substr(authority_start, authority_end == std::string::npos ? std::string::npos : authority_end - authority_start);
    if (authority.empty()) return scheme + "://local";
    return scheme + "://" + authority;
}

static std::string requestHeader(ICoreWebView2HttpRequestHeaders *headers, const wchar_t *name) {
    if (!headers) return std::string();
    LPWSTR value_w = nullptr;
    if (FAILED(headers->GetHeader(name, &value_w)) || !value_w) return std::string();
    std::string value = narrow(value_w);
    CoTaskMemFree(value_w);
    return value;
}

static std::string originForResourceRequest(ICoreWebView2WebResourceRequest *request, const Window &window) {
    ComPtr<ICoreWebView2HttpRequestHeaders> headers;
    if (request && SUCCEEDED(request->get_Headers(&headers)) && headers) {
        std::string origin = requestHeader(headers.Get(), L"Origin");
        if (!origin.empty() && origin != "null") return originForUrl(origin);
        std::string referer = requestHeader(headers.Get(), L"Referer");
        if (!referer.empty()) return originForUrl(referer);
    }
    return window.current_origin;
}

static int hexValue(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static std::string percentDecodePathSegment(const std::string &value) {
    std::string out;
    out.reserve(value.size());
    for (size_t i = 0; i < value.size(); ++i) {
        if (value[i] == '%' && i + 2 < value.size()) {
            int hi = hexValue(value[i + 1]);
            int lo = hexValue(value[i + 2]);
            if (hi >= 0 && lo >= 0) {
                out.push_back((char)((hi << 4) | lo));
                i += 2;
                continue;
            }
        }
        out.push_back(value[i]);
    }
    return out;
}

static std::string resourceIdFromUri(const std::string &uri) {
    const std::string prefix = "zero://native/resource/";
    if (uri.rfind(prefix, 0) != 0) return std::string();
    size_t start = prefix.size();
    size_t end = uri.find_first_of("?#", start);
    return percentDecodePathSegment(uri.substr(start, end == std::string::npos ? std::string::npos : end - start));
}

static std::string mimeForPath(const std::string &path) {
    std::string lower = lowerAscii(path);
    if (lower.size() >= 5 && lower.substr(lower.size() - 5) == ".html") return "text/html";
    if (lower.size() >= 4 && lower.substr(lower.size() - 4) == ".css") return "text/css";
    if (lower.size() >= 3 && lower.substr(lower.size() - 3) == ".js") return "text/javascript";
    if (lower.size() >= 5 && lower.substr(lower.size() - 5) == ".json") return "application/json";
    if (lower.size() >= 4 && lower.substr(lower.size() - 4) == ".png") return "image/png";
    if (lower.size() >= 4 && lower.substr(lower.size() - 4) == ".svg") return "image/svg+xml";
    return "application/octet-stream";
}

static std::string safeAssetPathFromUri(const std::string &uri, const std::string &entry) {
    size_t scheme = uri.find("://");
    size_t path_start = scheme == std::string::npos ? 0 : uri.find('/', scheme + 3);
    std::string path = path_start == std::string::npos ? "/" : uri.substr(path_start);
    size_t end = path.find_first_of("?#");
    if (end != std::string::npos) path = path.substr(0, end);
    while (!path.empty() && path[0] == '/') path.erase(path.begin());
    if (path.empty()) path = entry.empty() ? "index.html" : entry;
    path = percentDecodePathSegment(path);
    if (path.empty() || path[0] == '/' || path.find('\\') != std::string::npos) return std::string();
    size_t segment_start = 0;
    while (segment_start <= path.size()) {
        size_t slash = path.find('/', segment_start);
        std::string segment = path.substr(segment_start, slash == std::string::npos ? std::string::npos : slash - segment_start);
        if (segment.empty() || segment == "." || segment == "..") return std::string();
        if (slash == std::string::npos) break;
        segment_start = slash + 1;
    }
    return path;
}

static void emit(Host *host, const Window &window, EventKind kind) {
    if (!host || !host->callback) return;
    RECT rect = {};
    if (window.hwnd) GetClientRect(window.hwnd, &rect);
    WindowsEvent event = {};
    event.kind = kind;
    event.window_id = window.id;
    event.width = rect.right > rect.left ? (double)(rect.right - rect.left) : window.width;
    event.height = rect.bottom > rect.top ? (double)(rect.bottom - rect.top) : window.height;
    event.scale = 1.0;
    event.x = window.x;
    event.y = window.y;
    event.open = window.hwnd != nullptr;
    event.focused = window.hwnd && GetFocus() == window.hwnd;
    event.label = window.label.c_str();
    event.label_len = window.label.size();
    event.title = window.title.c_str();
    event.title_len = window.title.size();
    host->callback(host->callback_context, &event);
}

static Host *hostFromWindow(HWND hwnd) {
    return reinterpret_cast<Host *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
}

static void closeResource(const std::shared_ptr<DynamicResource> &resource, int reason) {
    if (!resource || !resource->streaming || !resource->close_callback) return;
    std::lock_guard<std::mutex> lock(resource->stream_mutex);
    if (resource->closed) return;
    resource->closed = true;
    resource->close_callback(resource->stream_context, resource->id.c_str(), resource->id.size(), reason);
}

static void pruneExpiredResources(Host *host, int64_t now_ns) {
    std::vector<std::shared_ptr<DynamicResource>> expired;
    {
        std::lock_guard<std::mutex> lock(host->resource_mutex);
        for (auto it = host->resources.begin(); it != host->resources.end();) {
            auto resource = it->second;
            if (resource->has_expiry && now_ns >= resource->expires_at_ns) {
                expired.push_back(resource);
                it = host->resources.erase(it);
            } else {
                ++it;
            }
        }
    }
    for (auto &resource : expired) closeResource(resource, kResourceExpired);
}

static std::shared_ptr<DynamicResource> claimResource(Host *host, const std::string &id, const std::string &origin, uint64_t window_id, int64_t now_ns) {
    std::shared_ptr<DynamicResource> resource;
    {
        std::lock_guard<std::mutex> lock(host->resource_mutex);
        auto it = host->resources.find(id);
        if (it == host->resources.end()) return nullptr;
        resource = it->second;
        if (resource->has_expiry && now_ns >= resource->expires_at_ns) {
            host->resources.erase(it);
        } else if ((!resource->origin.empty() && resource->origin != origin) || (resource->window_id != 0 && resource->window_id != window_id)) {
            return nullptr;
        } else {
            if (resource->one_shot) host->resources.erase(it);
            return resource;
        }
    }
    closeResource(resource, kResourceExpired);
    return nullptr;
}

class MemoryStream final : public IStream {
public:
    explicit MemoryStream(std::vector<uint8_t> data) : data_(std::move(data)) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppvObject) override {
        if (!ppvObject) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_ISequentialStream || riid == IID_IStream) {
            *ppvObject = static_cast<IStream *>(this);
            AddRef();
            return S_OK;
        }
        *ppvObject = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_count_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = --ref_count_;
        if (count == 0) delete this;
        return count;
    }

    HRESULT STDMETHODCALLTYPE Read(void *pv, ULONG cb, ULONG *pcbRead) override {
        if (pcbRead) *pcbRead = 0;
        if (!pv && cb > 0) return STG_E_INVALIDPOINTER;
        if (cb == 0) return S_OK;
        ULONG count = (ULONG)std::min<size_t>(cb, data_.size() - offset_);
        if (count > 0) {
            memcpy(pv, data_.data() + offset_, count);
            offset_ += count;
        }
        if (pcbRead) *pcbRead = count;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Write(const void *, ULONG, ULONG *) override { return STG_E_ACCESSDENIED; }
    HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER move, DWORD origin, ULARGE_INTEGER *new_position) override {
        int64_t base = 0;
        if (origin == STREAM_SEEK_SET) base = 0;
        else if (origin == STREAM_SEEK_CUR) base = (int64_t)offset_;
        else if (origin == STREAM_SEEK_END) base = (int64_t)data_.size();
        else return STG_E_INVALIDFUNCTION;
        int64_t next = base + move.QuadPart;
        if (next < 0) return STG_E_INVALIDFUNCTION;
        offset_ = std::min<size_t>((size_t)next, data_.size());
        if (new_position) new_position->QuadPart = offset_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override { return STG_E_ACCESSDENIED; }
    HRESULT STDMETHODCALLTYPE CopyTo(IStream *, ULARGE_INTEGER, ULARGE_INTEGER *, ULARGE_INTEGER *) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE Commit(DWORD) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE Revert() override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE Stat(STATSTG *pstatstg, DWORD) override {
        if (!pstatstg) return STG_E_INVALIDPOINTER;
        memset(pstatstg, 0, sizeof(*pstatstg));
        pstatstg->type = STGTY_STREAM;
        pstatstg->cbSize.QuadPart = data_.size();
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Clone(IStream **) override { return STG_E_INVALIDFUNCTION; }

private:
    std::atomic<ULONG> ref_count_{1};
    std::vector<uint8_t> data_;
    size_t offset_ = 0;
};

class ResourceCallbackStream final : public IStream {
public:
    ResourceCallbackStream(std::shared_ptr<DynamicResource> resource, std::string origin, uint64_t window_id)
        : resource_(std::move(resource)), origin_(std::move(origin)), window_id_(window_id) {}

    ~ResourceCallbackStream() {
        closeOnce(kResourceCancel);
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppvObject) override {
        if (!ppvObject) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_ISequentialStream || riid == IID_IStream) {
            *ppvObject = static_cast<IStream *>(this);
            AddRef();
            return S_OK;
        }
        *ppvObject = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_count_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG count = --ref_count_;
        if (count == 0) delete this;
        return count;
    }

    HRESULT STDMETHODCALLTYPE Read(void *pv, ULONG cb, ULONG *pcbRead) override {
        if (pcbRead) *pcbRead = 0;
        if (!pv && cb > 0) return STG_E_INVALIDPOINTER;
        if (cb == 0) return S_OK;
        if (!resource_ || !resource_->read_callback) return STG_E_READFAULT;
        std::lock_guard<std::mutex> lock(resource_->stream_mutex);
        if (resource_->closed || resource_->eof) return S_OK;
        intptr_t count = resource_->read_callback(
            resource_->stream_context,
            resource_->id.c_str(),
            resource_->id.size(),
            origin_.c_str(),
            origin_.size(),
            window_id_,
            static_cast<char *>(pv),
            cb);
        if (count < 0 || (uint64_t)count > cb) {
            resource_->failed = true;
            closeOnceLocked(kResourceFailure);
            return STG_E_READFAULT;
        }
        if (pcbRead) *pcbRead = (ULONG)count;
        if (count == 0) {
            resource_->eof = true;
            closeOnceLocked(kResourceComplete);
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Write(const void *, ULONG, ULONG *) override { return STG_E_ACCESSDENIED; }
    HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER, DWORD, ULARGE_INTEGER *) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override { return STG_E_ACCESSDENIED; }
    HRESULT STDMETHODCALLTYPE CopyTo(IStream *, ULARGE_INTEGER, ULARGE_INTEGER *, ULARGE_INTEGER *) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE Commit(DWORD) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE Revert() override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return STG_E_INVALIDFUNCTION; }
    HRESULT STDMETHODCALLTYPE Stat(STATSTG *pstatstg, DWORD) override {
        if (!pstatstg) return STG_E_INVALIDPOINTER;
        memset(pstatstg, 0, sizeof(*pstatstg));
        pstatstg->type = STGTY_STREAM;
        if (resource_ && resource_->has_size) pstatstg->cbSize.QuadPart = resource_->size;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Clone(IStream **) override { return STG_E_INVALIDFUNCTION; }

private:
    void closeOnce(int reason) {
        if (!resource_) return;
        std::lock_guard<std::mutex> lock(resource_->stream_mutex);
        closeOnceLocked(reason);
    }

    void closeOnceLocked(int reason) {
        if (!resource_ || resource_->closed || !resource_->close_callback) return;
        resource_->closed = true;
        resource_->close_callback(resource_->stream_context, resource_->id.c_str(), resource_->id.size(), reason);
    }

    std::atomic<ULONG> ref_count_{1};
    std::shared_ptr<DynamicResource> resource_;
    std::string origin_;
    uint64_t window_id_ = 0;
};

static void createResponse(Host *host, IStream *stream, int status, const wchar_t *reason, const std::string &mime, uint64_t length, bool has_length, ICoreWebView2WebResourceResponse **response) {
    if (!host || !host->environment || !response) return;
    std::wstring headers = L"Content-Type: " + widen(mime.empty() ? "application/octet-stream" : mime) + L"\r\n";
    if (has_length) {
        headers += L"Content-Length: " + std::to_wstring(length) + L"\r\n";
    }
    host->environment->CreateWebResourceResponse(stream, status, reason, headers.c_str(), response);
}

static void createTextResponse(Host *host, int status, const wchar_t *reason, const char *message, ICoreWebView2WebResourceResponse **response) {
    std::vector<uint8_t> bytes(message, message + strlen(message));
    ComPtr<IStream> stream;
    stream.Attach(new MemoryStream(std::move(bytes)));
    createResponse(host, stream.Get(), status, reason, "text/plain", strlen(message), true, response);
}

static bool serveDynamicResource(Host *host, Window &window, const std::string &uri, const std::string &request_origin, ICoreWebView2WebResourceRequestedEventArgs *args) {
    std::string resource_id = resourceIdFromUri(uri);
    if (resource_id.empty()) return false;
    std::shared_ptr<DynamicResource> resource = claimResource(host, resource_id, request_origin, window.id, nowNanoseconds());
    ComPtr<ICoreWebView2WebResourceResponse> response;
    if (!resource) {
        createTextResponse(host, 404, L"Not Found", "Resource is not registered", &response);
    } else if (resource->streaming) {
        ComPtr<IStream> stream;
        stream.Attach(new ResourceCallbackStream(resource, request_origin, window.id));
        createResponse(host, stream.Get(), 200, L"OK", resource->mime, resource->size, resource->has_size, &response);
    } else {
        ComPtr<IStream> stream;
        stream.Attach(new MemoryStream(resource->bytes));
        createResponse(host, stream.Get(), 200, L"OK", resource->mime, resource->bytes.size(), true, &response);
    }
    if (response) args->put_Response(response.Get());
    return true;
}

static bool serveAssetResource(Host *host, Window &window, const std::string &uri, ICoreWebView2WebResourceRequestedEventArgs *args) {
    if (window.source_kind != 2) return false;
    if (originForUrl(uri) != window.current_origin) return false;
    std::string relative = safeAssetPathFromUri(uri, window.asset_entry);
    if (relative.empty()) return false;
    std::string full_path = window.asset_root;
    if (!full_path.empty() && full_path.back() != '\\' && full_path.back() != '/') full_path.push_back('\\');
    full_path += relative;
    std::ifstream file(full_path, std::ios::binary);
    if (!file && window.spa_fallback) {
        full_path = window.asset_root;
        if (!full_path.empty() && full_path.back() != '\\' && full_path.back() != '/') full_path.push_back('\\');
        full_path += window.asset_entry.empty() ? "index.html" : window.asset_entry;
        file.open(full_path, std::ios::binary);
    }
    if (!file) return false;
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    ComPtr<IStream> stream;
    stream.Attach(new MemoryStream(bytes));
    ComPtr<ICoreWebView2WebResourceResponse> response;
    createResponse(host, stream.Get(), 200, L"OK", mimeForPath(full_path), bytes.size(), true, &response);
    if (response) args->put_Response(response.Get());
    return true;
}

static void navigateWindow(Window &window) {
    if (!window.webview) return;
    if (window.source_kind == 0) {
        window.current_origin = "zero://inline";
        window.webview->NavigateToString(widen(window.source).c_str());
    } else if (window.source_kind == 1) {
        window.current_origin = originForUrl(window.source);
        window.webview->Navigate(widen(window.source).c_str());
    } else {
        window.current_origin = window.asset_origin.empty() ? "zero://app" : window.asset_origin;
        std::string entry = window.asset_entry.empty() ? "index.html" : window.asset_entry;
        window.webview->Navigate(widen(window.current_origin + "/" + entry).c_str());
    }
}

static void initializeWebView(Host *host, uint64_t window_id);

static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
        auto *host = reinterpret_cast<Host *>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(host));
    }
    Host *host = hostFromWindow(hwnd);
    switch (message) {
        case WM_SIZE:
            if (host) {
                RECT bounds;
                GetClientRect(hwnd, &bounds);
                for (auto &entry : host->windows) {
                    if (entry.second.hwnd == hwnd) {
                        if (entry.second.controller) entry.second.controller->put_Bounds(bounds);
                        emit(host, entry.second, kResize);
                    }
                }
            }
            return 0;
        case WM_SETFOCUS:
        case WM_KILLFOCUS:
        case WM_MOVE:
            if (host) {
                for (auto &entry : host->windows) {
                    if (entry.second.hwnd == hwnd) emit(host, entry.second, kWindowFrame);
                }
            }
            return 0;
        case WM_TIMER:
            if (host) {
                for (auto &entry : host->windows) emit(host, entry.second, kFrame);
            }
            return 0;
        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            if (host) {
                for (auto &entry : host->windows) {
                    if (entry.second.hwnd == hwnd) {
                        entry.second.webview.Reset();
                        entry.second.controller.Reset();
                        entry.second.hwnd = nullptr;
                        emit(host, entry.second, kWindowFrame);
                    }
                }
                bool any_open = false;
                for (auto &entry : host->windows) any_open = any_open || entry.second.hwnd;
                if (!any_open) PostQuitMessage(0);
            }
            return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

static ATOM registerClass(Host *host) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = windowProc;
    wc.hInstance = host->instance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = L"ZeroNativeWindowsHost";
    return RegisterClassExW(&wc);
}

static bool createNativeWindow(Host *host, Window &window) {
    registerClass(host);
    std::wstring title = widen(window.title.empty() ? host->window_title : window.title);
    HWND hwnd = CreateWindowExW(
        0,
        L"ZeroNativeWindowsHost",
        title.c_str(),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        (int)window.width,
        (int)window.height,
        nullptr,
        nullptr,
        host->instance,
        host);
    if (!hwnd) return false;
    window.hwnd = hwnd;
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    SetTimer(hwnd, 1, 16, nullptr);
    initializeWebView(host, window.id);
    return true;
}

static void setupWebView(Host *host, Window &window) {
    if (!window.webview) return;
    window.webview->AddScriptToExecuteOnDocumentCreated(widen(std::string(ZERO_NATIVE_BRIDGE_SCRIPT)).c_str(), nullptr);
    window.webview->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>(
        [host, window_id = window.id](ICoreWebView2 *, ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
            if (!host || !host->bridge_callback || !args) return S_OK;
            LPWSTR message_w = nullptr;
            if (FAILED(args->TryGetWebMessageAsString(&message_w)) || !message_w) return S_OK;
            std::string message = narrow(message_w);
            CoTaskMemFree(message_w);
            LPWSTR source_w = nullptr;
            std::string origin = "zero://inline";
            if (SUCCEEDED(args->get_Source(&source_w)) && source_w) {
                origin = originForUrl(narrow(source_w));
                CoTaskMemFree(source_w);
            }
            auto found = host->windows.find(window_id);
            if (found != host->windows.end()) found->second.current_origin = origin;
            host->bridge_callback(host->bridge_context, window_id, message.c_str(), message.size(), origin.c_str(), origin.size());
            return S_OK;
        }).Get(),
        &window.message_token);
    window.webview->add_SourceChanged(Callback<ICoreWebView2SourceChangedEventHandler>(
        [host, window_id = window.id](ICoreWebView2 *sender, ICoreWebView2SourceChangedEventArgs *) -> HRESULT {
            if (!host || !sender) return S_OK;
            LPWSTR source_w = nullptr;
            if (FAILED(sender->get_Source(&source_w)) || !source_w) return S_OK;
            std::string origin = originForUrl(narrow(source_w));
            CoTaskMemFree(source_w);
            auto found = host->windows.find(window_id);
            if (found != host->windows.end()) found->second.current_origin = origin;
            return S_OK;
        }).Get(),
        &window.source_token);
    window.webview->AddWebResourceRequestedFilter(L"zero://*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    window.webview->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>(
        [host, window_id = window.id](ICoreWebView2 *, ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
            if (!host || !args) return S_OK;
            auto found = host->windows.find(window_id);
            if (found == host->windows.end()) return S_OK;
            ComPtr<ICoreWebView2WebResourceRequest> request;
            if (FAILED(args->get_Request(&request)) || !request) return S_OK;
            LPWSTR uri_w = nullptr;
            if (FAILED(request->get_Uri(&uri_w)) || !uri_w) return S_OK;
            std::string uri = narrow(uri_w);
            CoTaskMemFree(uri_w);
            const std::string request_origin = originForResourceRequest(request.Get(), found->second);
            if (serveDynamicResource(host, found->second, uri, request_origin, args)) return S_OK;
            if (serveAssetResource(host, found->second, uri, args)) return S_OK;
            ComPtr<ICoreWebView2WebResourceResponse> response;
            createTextResponse(host, 404, L"Not Found", "Resource not found", &response);
            if (response) args->put_Response(response.Get());
            return S_OK;
        }).Get(),
        &window.resource_token);
}

static bool loadWebView2Loader(Host *host) {
    if (host->create_environment) return true;
    host->webview2_loader = LoadLibraryW(L"WebView2Loader.dll");
    if (!host->webview2_loader) return false;
    host->create_environment = reinterpret_cast<CreateCoreWebView2EnvironmentWithOptionsFn>(GetProcAddress(host->webview2_loader, "CreateCoreWebView2EnvironmentWithOptions"));
    return host->create_environment != nullptr;
}

static void initializeWebView(Host *host, uint64_t window_id) {
    if (!host || !loadWebView2Loader(host)) return;
    auto found = host->windows.find(window_id);
    if (found == host->windows.end() || !found->second.hwnd) return;
    if (host->environment) {
        host->environment->CreateCoreWebView2Controller(found->second.hwnd, Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [host, window_id](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
                if (FAILED(result) || !controller) return S_OK;
                auto window_found = host->windows.find(window_id);
                if (window_found == host->windows.end()) return S_OK;
                Window &window = window_found->second;
                window.controller = controller;
                window.controller->get_CoreWebView2(&window.webview);
                RECT bounds;
                GetClientRect(window.hwnd, &bounds);
                window.controller->put_Bounds(bounds);
                setupWebView(host, window);
                navigateWindow(window);
                return S_OK;
            }).Get());
        return;
    }
    if (host->environment_requested) return;
    host->environment_requested = true;
    wchar_t temp_path[MAX_PATH] = {};
    DWORD temp_len = GetTempPathW(MAX_PATH, temp_path);
    std::wstring user_data = temp_len > 0 ? std::wstring(temp_path, temp_len) + L"zero-native-webview2" : L"zero-native-webview2";
    host->create_environment(nullptr, user_data.c_str(), nullptr, Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [host, window_id](HRESULT result, ICoreWebView2Environment *environment) -> HRESULT {
            host->environment_requested = false;
            if (FAILED(result) || !environment) return S_OK;
            host->environment = environment;
            initializeWebView(host, window_id);
            for (auto &entry : host->windows) {
                if (entry.first != window_id && entry.second.hwnd && !entry.second.webview) initializeWebView(host, entry.first);
            }
            return S_OK;
        }).Get());
}

static int registerResource(Host *host, std::shared_ptr<DynamicResource> resource) {
    if (!host || !resource || resource->id.empty()) return kResourceInvalidArgument;
    pruneExpiredResources(host, nowNanoseconds());
    std::shared_ptr<DynamicResource> old;
    {
        std::lock_guard<std::mutex> lock(host->resource_mutex);
        auto existing = host->resources.find(resource->id);
        if (existing == host->resources.end() && host->resources.size() >= kMaxDynamicResources) return kResourceLimit;
        if (existing != host->resources.end()) {
            old = existing->second;
            host->resources.erase(existing);
        }
        host->resources[resource->id] = resource;
    }
    closeResource(old, kResourceRevoke);
    return kResourceOk;
}

} // namespace

extern "C" {

void zero_native_windows_load_window_webview(Host *host, uint64_t window_id, const char *source, size_t source_len, int source_kind, const char *asset_root, size_t asset_root_len, const char *asset_entry, size_t asset_entry_len, const char *asset_origin, size_t asset_origin_len, int spa_fallback);
void zero_native_windows_bridge_respond_window(Host *host, uint64_t window_id, const char *response, size_t response_len);

Host *zero_native_windows_create(const char *app_name, size_t app_name_len, const char *window_title, size_t window_title_len, const char *bundle_id, size_t bundle_id_len, const char *icon_path, size_t icon_path_len, const char *window_label, size_t window_label_len, double x, double y, double width, double height, int restore_frame) {
    (void)restore_frame;
    Host *host = new Host();
    host->app_name = slice(app_name, app_name_len);
    host->window_title = slice(window_title, window_title_len);
    host->bundle_id = slice(bundle_id, bundle_id_len);
    host->icon_path = slice(icon_path, icon_path_len);
    Window window;
    window.id = 1;
    window.label = slice(window_label, window_label_len);
    window.title = host->window_title.empty() ? host->app_name : host->window_title;
    window.x = x;
    window.y = y;
    window.width = width;
    window.height = height;
    host->windows[window.id] = window;
    return host;
}

void zero_native_windows_destroy(Host *host) {
    if (!host) return;
    std::vector<std::shared_ptr<DynamicResource>> resources;
    {
        std::lock_guard<std::mutex> lock(host->resource_mutex);
        for (auto &entry : host->resources) resources.push_back(entry.second);
        host->resources.clear();
    }
    for (auto &resource : resources) closeResource(resource, kResourceRevoke);
    if (host->webview2_loader) FreeLibrary(host->webview2_loader);
    delete host;
}

void zero_native_windows_run(Host *host, EventCallback callback, void *context) {
    if (!host) return;
    host->callback = callback;
    host->callback_context = context;
    host->running = true;
    if (!host->windows.empty()) createNativeWindow(host, host->windows.begin()->second);
    WindowsEvent start = {};
    start.kind = kStart;
    start.window_id = 1;
    callback(context, &start);
    for (auto &entry : host->windows) {
        emit(host, entry.second, kResize);
        emit(host, entry.second, kWindowFrame);
    }
    MSG message = {};
    while (host->running && GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    WindowsEvent shutdown = {};
    shutdown.kind = kShutdown;
    shutdown.window_id = 1;
    callback(context, &shutdown);
}

void zero_native_windows_stop(Host *host) {
    if (!host) return;
    host->running = false;
    PostQuitMessage(0);
}

void zero_native_windows_load_webview(Host *host, const char *source, size_t source_len, int source_kind, const char *asset_root, size_t asset_root_len, const char *asset_entry, size_t asset_entry_len, const char *asset_origin, size_t asset_origin_len, int spa_fallback) {
    zero_native_windows_load_window_webview(host, 1, source, source_len, source_kind, asset_root, asset_root_len, asset_entry, asset_entry_len, asset_origin, asset_origin_len, spa_fallback);
}

void zero_native_windows_load_window_webview(Host *host, uint64_t window_id, const char *source, size_t source_len, int source_kind, const char *asset_root, size_t asset_root_len, const char *asset_entry, size_t asset_entry_len, const char *asset_origin, size_t asset_origin_len, int spa_fallback) {
    if (!host) return;
    auto found = host->windows.find(window_id);
    if (found == host->windows.end()) return;
    Window &window = found->second;
    window.source = slice(source, source_len);
    window.source_kind = source_kind;
    window.asset_root = slice(asset_root, asset_root_len);
    window.asset_entry = slice(asset_entry, asset_entry_len);
    window.asset_origin = slice(asset_origin, asset_origin_len);
    window.spa_fallback = spa_fallback;
    if (source_kind == 1) window.current_origin = originForUrl(window.source);
    else if (source_kind == 2) window.current_origin = window.asset_origin.empty() ? "zero://app" : window.asset_origin;
    else window.current_origin = "zero://inline";
    if (window.webview) navigateWindow(window);
    emit(host, window, kWindowFrame);
}

void zero_native_windows_set_bridge_callback(Host *host, BridgeCallback callback, void *context) {
    if (!host) return;
    host->bridge_callback = callback;
    host->bridge_context = context;
}

void zero_native_windows_bridge_respond(Host *host, const char *response, size_t response_len) {
    zero_native_windows_bridge_respond_window(host, 1, response, response_len);
}

void zero_native_windows_bridge_respond_window(Host *host, uint64_t window_id, const char *response, size_t response_len) {
    if (!host) return;
    auto found = host->windows.find(window_id);
    if (found == host->windows.end() || !found->second.webview) return;
    std::string payload = slice(response, response_len);
    std::wstring script = L"window.zero&&window.zero._complete(" + widen(payload.empty() ? "{}" : payload) + L");";
    found->second.webview->ExecuteScript(script.c_str(), nullptr);
}

void zero_native_windows_emit_window_event(Host *host, uint64_t window_id, const char *name, size_t name_len, const char *detail_json, size_t detail_json_len) {
    if (!host) return;
    auto found = host->windows.find(window_id);
    if (found == host->windows.end() || !found->second.webview) return;
    std::string event_name = slice(name, name_len);
    std::string detail = slice(detail_json, detail_json_len);
    std::wstring script = L"window.zero&&window.zero._emit(" + widen("\"" + event_name + "\"") + L"," + widen(detail.empty() ? "null" : detail) + L");";
    found->second.webview->ExecuteScript(script.c_str(), nullptr);
}

void zero_native_windows_set_security_policy(Host *host, const char *allowed_origins, size_t allowed_origins_len, const char *external_urls, size_t external_urls_len, int external_action) {
    (void)host;
    (void)allowed_origins;
    (void)allowed_origins_len;
    (void)external_urls;
    (void)external_urls_len;
    (void)external_action;
}

int zero_native_windows_register_resource_bytes(Host *host, const char *id, size_t id_len, const char *mime, size_t mime_len, const char *bytes, size_t bytes_len, const char *origin, size_t origin_len, uint64_t window_id, int64_t expires_at_ns, int has_expiry, int one_shot) {
    if (!host || !id || id_len == 0 || (!bytes && bytes_len > 0)) return kResourceInvalidArgument;
    auto resource = std::make_shared<DynamicResource>();
    if (!resource) return kResourceOutOfMemory;
    resource->id = slice(id, id_len);
    resource->mime = mime && mime_len > 0 ? slice(mime, mime_len) : "application/octet-stream";
    resource->origin = slice(origin, origin_len);
    resource->window_id = window_id;
    resource->expires_at_ns = expires_at_ns;
    resource->has_expiry = has_expiry != 0;
    resource->one_shot = one_shot != 0;
    resource->streaming = false;
    if (bytes_len > 0) resource->bytes.assign((const uint8_t *)bytes, (const uint8_t *)bytes + bytes_len);
    return registerResource(host, resource);
}

int zero_native_windows_register_resource_stream(Host *host, const char *id, size_t id_len, const char *mime, size_t mime_len, const char *origin, size_t origin_len, uint64_t window_id, int64_t expires_at_ns, int has_expiry, int one_shot, uint64_t size, int has_size, void *callback_context, ResourceStreamReadCallback read_callback, ResourceStreamCloseCallback close_callback) {
    if (!host || !id || id_len == 0 || !read_callback || !close_callback || !one_shot) return kResourceInvalidArgument;
    auto resource = std::make_shared<DynamicResource>();
    if (!resource) return kResourceOutOfMemory;
    resource->id = slice(id, id_len);
    resource->mime = mime && mime_len > 0 ? slice(mime, mime_len) : "application/octet-stream";
    resource->origin = slice(origin, origin_len);
    resource->window_id = window_id;
    resource->expires_at_ns = expires_at_ns;
    resource->has_expiry = has_expiry != 0;
    resource->one_shot = true;
    resource->streaming = true;
    resource->size = size;
    resource->has_size = has_size != 0;
    resource->stream_context = callback_context;
    resource->read_callback = read_callback;
    resource->close_callback = close_callback;
    return registerResource(host, resource);
}

void zero_native_windows_revoke_resource(Host *host, const char *id, size_t id_len) {
    if (!host || !id || id_len == 0) return;
    std::shared_ptr<DynamicResource> resource;
    std::string resource_id = slice(id, id_len);
    {
        std::lock_guard<std::mutex> lock(host->resource_mutex);
        auto found = host->resources.find(resource_id);
        if (found == host->resources.end()) return;
        resource = found->second;
        host->resources.erase(found);
    }
    closeResource(resource, kResourceRevoke);
}

int zero_native_windows_create_window(Host *host, uint64_t window_id, const char *window_title, size_t window_title_len, const char *window_label, size_t window_label_len, double x, double y, double width, double height, int restore_frame) {
    (void)restore_frame;
    if (!host || host->windows.find(window_id) != host->windows.end()) return 0;
    Window window;
    window.id = window_id;
    window.title = slice(window_title, window_title_len);
    window.label = slice(window_label, window_label_len);
    window.x = x;
    window.y = y;
    window.width = width;
    window.height = height;
    host->windows[window_id] = window;
    bool ok = createNativeWindow(host, host->windows[window_id]);
    return ok ? 1 : 0;
}

int zero_native_windows_focus_window(Host *host, uint64_t window_id) {
    if (!host) return 0;
    auto found = host->windows.find(window_id);
    if (found == host->windows.end() || !found->second.hwnd) return 0;
    SetForegroundWindow(found->second.hwnd);
    SetFocus(found->second.hwnd);
    return 1;
}

int zero_native_windows_close_window(Host *host, uint64_t window_id) {
    if (!host) return 0;
    auto found = host->windows.find(window_id);
    if (found == host->windows.end() || !found->second.hwnd) return 0;
    DestroyWindow(found->second.hwnd);
    return 1;
}

size_t zero_native_windows_clipboard_read(Host *host, char *buffer, size_t buffer_len) {
    (void)host;
    if (!buffer || buffer_len == 0 || !OpenClipboard(nullptr)) return 0;
    HANDLE handle = GetClipboardData(CF_TEXT);
    if (!handle) {
        CloseClipboard();
        return 0;
    }
    const char *text = static_cast<const char *>(GlobalLock(handle));
    if (!text) {
        CloseClipboard();
        return 0;
    }
    size_t len = boundedLen(text, buffer_len);
    memcpy(buffer, text, len);
    GlobalUnlock(handle);
    CloseClipboard();
    return len;
}

void zero_native_windows_clipboard_write(Host *host, const char *text, size_t text_len) {
    (void)host;
    if (!OpenClipboard(nullptr)) return;
    EmptyClipboard();
    HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, text_len + 1);
    if (handle) {
        char *dest = static_cast<char *>(GlobalLock(handle));
        memcpy(dest, text, text_len);
        dest[text_len] = '\0';
        GlobalUnlock(handle);
        SetClipboardData(CF_TEXT, handle);
    }
    CloseClipboard();
}

}

#endif
