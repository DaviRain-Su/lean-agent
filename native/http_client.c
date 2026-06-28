#include <lean/lean.h>
#include <curl/curl.h>
#include <stdint.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct response_buffer {
    char *data;
    size_t size;
    size_t limit;
    int too_large;
};

static size_t write_response(void *contents, size_t size, size_t nmemb, void *userp) {
    if (size != 0 && nmemb > SIZE_MAX / size) {
        struct response_buffer *buffer = (struct response_buffer *)userp;
        buffer->too_large = 1;
        return 0;
    }

    size_t real_size = size * nmemb;
    struct response_buffer *buffer = (struct response_buffer *)userp;

    if (real_size > buffer->limit - buffer->size) {
        buffer->too_large = 1;
        return 0;
    }
    if (buffer->size > SIZE_MAX - real_size - 1) {
        buffer->too_large = 1;
        return 0;
    }

    char *next = realloc(buffer->data, buffer->size + real_size + 1);
    if (next == NULL) {
        return 0;
    }

    buffer->data = next;
    memcpy(&(buffer->data[buffer->size]), contents, real_size);
    buffer->size += real_size;
    buffer->data[buffer->size] = 0;
    return real_size;
}

static lean_obj_res io_error(const char *message) {
    return lean_io_result_mk_error(
        lean_mk_io_error_other_error(1, lean_mk_string(message))
    );
}

static lean_obj_res io_errorf_u64(const char *prefix, uint64_t value) {
    char message[256];
    snprintf(message, sizeof(message), "%s: %llu", prefix, (unsigned long long)value);
    return io_error(message);
}

static lean_obj_res io_errorf(const char *prefix, const char *detail) {
    size_t prefix_len = strlen(prefix);
    size_t detail_len = strlen(detail);
    char *message = malloc(prefix_len + detail_len + 3);
    if (message == NULL) {
        return io_error("native HTTP error");
    }
    memcpy(message, prefix, prefix_len);
    memcpy(message + prefix_len, ": ", 2);
    memcpy(message + prefix_len + 2, detail, detail_len);
    message[prefix_len + 2 + detail_len] = 0;
    lean_obj_res result = io_error(message);
    free(message);
    return result;
}

static CURLcode ensure_curl_global_init(void) {
    static int initialized = 0;
    static CURLcode init_code = CURLE_OK;
    if (!initialized) {
        init_code = curl_global_init(CURL_GLOBAL_DEFAULT);
        initialized = 1;
    }
    return init_code;
}

#define SETOPT_OR_GOTO(option, value) do { \
    CURLcode opt_code = curl_easy_setopt(curl, option, value); \
    if (opt_code != CURLE_OK) { \
        result = io_errorf("curl_easy_setopt " #option " failed", curl_easy_strerror(opt_code)); \
        goto cleanup; \
    } \
} while (0)

lean_obj_res lean_agent_http_post_json(
    lean_obj_arg lean_url,
    lean_obj_arg lean_api_key,
    lean_obj_arg lean_payload,
    lean_obj_arg lean_no_proxy,
    lean_obj_arg lean_user_agent,
    uint32_t timeout_seconds,
    uint32_t connect_timeout_seconds,
    uint64_t max_response_bytes
) {
    const char *url = lean_string_cstr(lean_url);
    const char *api_key = lean_string_cstr(lean_api_key);
    const char *payload = lean_string_cstr(lean_payload);
    const char *no_proxy = lean_string_cstr(lean_no_proxy);
    const char *user_agent = lean_string_cstr(lean_user_agent);
    lean_obj_res result = NULL;

    if (max_response_bytes == 0) {
        return io_error("maxResponseBytes must be greater than zero");
    }
    if (max_response_bytes > SIZE_MAX) {
        return io_errorf_u64("maxResponseBytes exceeds platform size_t", max_response_bytes);
    }

    size_t payload_len = strlen(payload);
    if (payload_len > LONG_MAX) {
        return io_error("request payload is too large");
    }

    CURLcode global_code = ensure_curl_global_init();
    if (global_code != CURLE_OK) {
        return io_errorf("curl_global_init failed", curl_easy_strerror(global_code));
    }

    CURL *curl = curl_easy_init();
    if (curl == NULL) {
        return io_error("curl_easy_init failed");
    }

    struct response_buffer response;
    response.data = malloc(1);
    response.size = 0;
    response.limit = (size_t)max_response_bytes;
    response.too_large = 0;
    if (response.data == NULL) {
        curl_easy_cleanup(curl);
        return io_error("failed to allocate response buffer");
    }
    response.data[0] = 0;
    char error_buffer[CURL_ERROR_SIZE];
    error_buffer[0] = 0;

    char *auth_header = NULL;
    struct curl_slist *headers = NULL;
    struct curl_slist *next_headers = curl_slist_append(headers, "Content-Type: application/json");
    if (next_headers == NULL) {
        result = io_error("failed to allocate content-type header");
        goto cleanup;
    }
    headers = next_headers;

    next_headers = curl_slist_append(headers, "Accept: application/json");
    if (next_headers == NULL) {
        result = io_error("failed to allocate accept header");
        goto cleanup;
    }
    headers = next_headers;

    size_t auth_prefix_len = strlen("Authorization: Bearer ");
    size_t key_len = strlen(api_key);
    auth_header = malloc(auth_prefix_len + key_len + 1);
    if (auth_header == NULL) {
        result = io_error("failed to allocate authorization header");
        goto cleanup;
    }
    memcpy(auth_header, "Authorization: Bearer ", auth_prefix_len);
    memcpy(auth_header + auth_prefix_len, api_key, key_len);
    auth_header[auth_prefix_len + key_len] = 0;
    next_headers = curl_slist_append(headers, auth_header);
    if (next_headers == NULL) {
        result = io_error("failed to allocate authorization header");
        goto cleanup;
    }
    headers = next_headers;

    SETOPT_OR_GOTO(CURLOPT_ERRORBUFFER, error_buffer);
    SETOPT_OR_GOTO(CURLOPT_URL, url);
    SETOPT_OR_GOTO(CURLOPT_HTTPHEADER, headers);
    SETOPT_OR_GOTO(CURLOPT_POST, 1L);
    SETOPT_OR_GOTO(CURLOPT_POSTFIELDS, payload);
    SETOPT_OR_GOTO(CURLOPT_POSTFIELDSIZE, (long)payload_len);
    SETOPT_OR_GOTO(CURLOPT_WRITEFUNCTION, write_response);
    SETOPT_OR_GOTO(CURLOPT_WRITEDATA, (void *)&response);
    SETOPT_OR_GOTO(CURLOPT_TIMEOUT, (long)timeout_seconds);
    SETOPT_OR_GOTO(CURLOPT_CONNECTTIMEOUT, (long)connect_timeout_seconds);
    SETOPT_OR_GOTO(CURLOPT_FOLLOWLOCATION, 0L);
    SETOPT_OR_GOTO(CURLOPT_USERAGENT, user_agent);
    SETOPT_OR_GOTO(CURLOPT_ACCEPT_ENCODING, "");
    if (no_proxy[0] != 0) {
        SETOPT_OR_GOTO(CURLOPT_NOPROXY, no_proxy);
    }
    /* Do not pin the TLS version; libcurl should negotiate with the server/proxy. */
    SETOPT_OR_GOTO(CURLOPT_NOSIGNAL, 1L);

    CURLcode code = curl_easy_perform(curl);
    if (code != CURLE_OK) {
        if (response.too_large) {
            result = io_errorf_u64("HTTP response exceeded maxResponseBytes", max_response_bytes);
        } else {
            const char *detail = error_buffer[0] == 0 ? curl_easy_strerror(code) : error_buffer;
            result = io_errorf("HTTP request failed", detail);
        }
        goto cleanup;
    }

    lean_object *lean_response = lean_mk_string(response.data);
    result = lean_io_result_mk_ok(lean_response);

cleanup:
    curl_slist_free_all(headers);
    free(auth_header);
    free(response.data);
    curl_easy_cleanup(curl);
    return result;
}
