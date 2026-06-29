#include <lean/lean.h>
#include <curl/curl.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
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

#define MAX_RESPONSE_HEADER_BYTES 262144

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

static size_t write_header(void *contents, size_t size, size_t nmemb, void *userp) {
    return write_response(contents, size, nmemb, userp);
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

static char *base64url_encode(const unsigned char *bytes, size_t len) {
    static const char alphabet[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    size_t full_chunks = len / 3;
    size_t rem = len % 3;
    size_t out_len = full_chunks * 4 + (rem == 0 ? 0 : rem + 1);
    char *out = malloc(out_len + 1);
    if (out == NULL) {
        return NULL;
    }

    size_t in = 0;
    size_t pos = 0;
    for (size_t i = 0; i < full_chunks; i++) {
        unsigned int value =
            ((unsigned int)bytes[in] << 16) |
            ((unsigned int)bytes[in + 1] << 8) |
            (unsigned int)bytes[in + 2];
        in += 3;
        out[pos++] = alphabet[(value >> 18) & 0x3f];
        out[pos++] = alphabet[(value >> 12) & 0x3f];
        out[pos++] = alphabet[(value >> 6) & 0x3f];
        out[pos++] = alphabet[value & 0x3f];
    }

    if (rem == 1) {
        unsigned int value = (unsigned int)bytes[in] << 16;
        out[pos++] = alphabet[(value >> 18) & 0x3f];
        out[pos++] = alphabet[(value >> 12) & 0x3f];
    } else if (rem == 2) {
        unsigned int value = ((unsigned int)bytes[in] << 16) | ((unsigned int)bytes[in + 1] << 8);
        out[pos++] = alphabet[(value >> 18) & 0x3f];
        out[pos++] = alphabet[(value >> 12) & 0x3f];
        out[pos++] = alphabet[(value >> 6) & 0x3f];
    }

    out[pos] = 0;
    return out;
}

lean_obj_res lean_agent_pkce_random_verifier(uint32_t byte_count) {
    if (byte_count == 0) {
        return io_error("PKCE verifier byte count must be greater than zero");
    }
    if (byte_count > 1024) {
        return io_error("PKCE verifier byte count is too large");
    }

    unsigned char *bytes = malloc((size_t)byte_count);
    if (bytes == NULL) {
        return io_error("failed to allocate PKCE verifier bytes");
    }
    if (RAND_bytes(bytes, (int)byte_count) != 1) {
        free(bytes);
        return io_error("RAND_bytes failed while generating PKCE verifier");
    }

    char *encoded = base64url_encode(bytes, (size_t)byte_count);
    free(bytes);
    if (encoded == NULL) {
        return io_error("failed to encode PKCE verifier");
    }

    lean_object *result = lean_mk_string(encoded);
    free(encoded);
    return lean_io_result_mk_ok(result);
}

lean_obj_res lean_agent_pkce_code_challenge(lean_obj_arg lean_verifier) {
    const char *verifier = lean_string_cstr(lean_verifier);
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256((const unsigned char *)verifier, strlen(verifier), digest);

    char *encoded = base64url_encode(digest, SHA256_DIGEST_LENGTH);
    if (encoded == NULL) {
        return io_error("failed to encode PKCE code challenge");
    }

    lean_object *result = lean_mk_string(encoded);
    free(encoded);
    return lean_io_result_mk_ok(result);
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

static int ascii_lower(int c) {
    if (c >= 'A' && c <= 'Z') {
        return c + ('a' - 'A');
    }
    return c;
}

static int header_line_matches(const char *line, size_t line_len, const char *name) {
    size_t name_len = strlen(name);
    size_t i = 0;
    while (i < line_len && (line[i] == ' ' || line[i] == '\t')) {
        i++;
    }
    if (i + name_len > line_len) {
        return 0;
    }
    for (size_t j = 0; j < name_len; j++) {
        if (ascii_lower((unsigned char)line[i + j]) != ascii_lower((unsigned char)name[j])) {
            return 0;
        }
    }
    i += name_len;
    while (i < line_len && (line[i] == ' ' || line[i] == '\t')) {
        i++;
    }
    return i < line_len && line[i] == ':';
}

static int header_block_has(const char *block, const char *name) {
    const char *line = block;
    while (*line != 0) {
        const char *line_end = strchr(line, '\n');
        size_t line_len = line_end == NULL ? strlen(line) : (size_t)(line_end - line);
        if (line_len > 0 && line[line_len - 1] == '\r') {
            line_len--;
        }
        if (header_line_matches(line, line_len, name)) {
            return 1;
        }
        if (line_end == NULL) {
            break;
        }
        line = line_end + 1;
    }
    return 0;
}

static int append_header_copy(struct curl_slist **headers, const char *line, size_t line_len) {
    if (line_len == 0) {
        return 1;
    }
    char *copy = malloc(line_len + 1);
    if (copy == NULL) {
        return 0;
    }
    memcpy(copy, line, line_len);
    copy[line_len] = 0;
    struct curl_slist *next_headers = curl_slist_append(*headers, copy);
    free(copy);
    if (next_headers == NULL) {
        return 0;
    }
    *headers = next_headers;
    return 1;
}

static int append_header_block(struct curl_slist **headers, const char *block) {
    const char *line = block;
    while (*line != 0) {
        const char *line_end = strchr(line, '\n');
        size_t line_len = line_end == NULL ? strlen(line) : (size_t)(line_end - line);
        if (line_len > 0 && line[line_len - 1] == '\r') {
            line_len--;
        }
        if (!append_header_copy(headers, line, line_len)) {
            return 0;
        }
        if (line_end == NULL) {
            break;
        }
        line = line_end + 1;
    }
    return 1;
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
    lean_obj_arg lean_extra_headers,
    uint32_t timeout_seconds,
    uint32_t connect_timeout_seconds,
    uint64_t max_response_bytes
) {
    const char *url = lean_string_cstr(lean_url);
    const char *api_key = lean_string_cstr(lean_api_key);
    const char *payload = lean_string_cstr(lean_payload);
    const char *no_proxy = lean_string_cstr(lean_no_proxy);
    const char *user_agent = lean_string_cstr(lean_user_agent);
    const char *extra_headers = lean_string_cstr(lean_extra_headers);
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

    struct response_buffer response_headers;
    response_headers.data = malloc(1);
    response_headers.size = 0;
    response_headers.limit = MAX_RESPONSE_HEADER_BYTES;
    response_headers.too_large = 0;
    if (response_headers.data == NULL) {
        free(response.data);
        curl_easy_cleanup(curl);
        return io_error("failed to allocate response header buffer");
    }
    response_headers.data[0] = 0;

    char error_buffer[CURL_ERROR_SIZE];
    error_buffer[0] = 0;

    char *auth_header = NULL;
    struct curl_slist *headers = NULL;
    if (!header_block_has(extra_headers, "Content-Type") &&
        !append_header_copy(&headers, "Content-Type: application/json", strlen("Content-Type: application/json"))) {
        result = io_error("failed to allocate content-type header");
        goto cleanup;
    }

    if (!header_block_has(extra_headers, "Accept") &&
        !append_header_copy(&headers, "Accept: application/json", strlen("Accept: application/json"))) {
        result = io_error("failed to allocate accept header");
        goto cleanup;
    }

    if (!header_block_has(extra_headers, "Authorization") && api_key[0] != 0) {
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
        if (!append_header_copy(&headers, auth_header, strlen(auth_header))) {
            result = io_error("failed to allocate authorization header");
            goto cleanup;
        }
    }

    if (!append_header_block(&headers, extra_headers)) {
        result = io_error("failed to allocate custom headers");
        goto cleanup;
    }

    SETOPT_OR_GOTO(CURLOPT_ERRORBUFFER, error_buffer);
    SETOPT_OR_GOTO(CURLOPT_URL, url);
    SETOPT_OR_GOTO(CURLOPT_HTTPHEADER, headers);
    SETOPT_OR_GOTO(CURLOPT_POST, 1L);
    SETOPT_OR_GOTO(CURLOPT_POSTFIELDS, payload);
    SETOPT_OR_GOTO(CURLOPT_POSTFIELDSIZE, (long)payload_len);
    SETOPT_OR_GOTO(CURLOPT_WRITEFUNCTION, write_response);
    SETOPT_OR_GOTO(CURLOPT_WRITEDATA, (void *)&response);
    SETOPT_OR_GOTO(CURLOPT_HEADERFUNCTION, write_header);
    SETOPT_OR_GOTO(CURLOPT_HEADERDATA, (void *)&response_headers);
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
        } else if (response_headers.too_large) {
            result = io_errorf_u64("HTTP response headers exceeded maxHeaderBytes", MAX_RESPONSE_HEADER_BYTES);
        } else {
            const char *detail = error_buffer[0] == 0 ? curl_easy_strerror(code) : error_buffer;
            result = io_errorf("HTTP request failed", detail);
        }
        goto cleanup;
    }

    long status_code = 0;
    CURLcode info_code = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status_code);
    if (info_code != CURLE_OK) {
        result = io_errorf("curl_easy_getinfo CURLINFO_RESPONSE_CODE failed", curl_easy_strerror(info_code));
        goto cleanup;
    }

    const char *magic = "LAHTTP2\n";
    size_t magic_len = strlen(magic);
    char status_line[32];
    int status_len = snprintf(status_line, sizeof(status_line), "%ld\n", status_code);
    if (status_len < 0 || (size_t)status_len >= sizeof(status_line)) {
        result = io_error("failed to format HTTP status");
        goto cleanup;
    }
    char header_len_line[32];
    int header_len_len = snprintf(header_len_line, sizeof(header_len_line), "%zu\n", response_headers.size);
    if (header_len_len < 0 || (size_t)header_len_len >= sizeof(header_len_line)) {
        result = io_error("failed to format HTTP header length");
        goto cleanup;
    }
    if (response.size > SIZE_MAX - magic_len - (size_t)status_len - (size_t)header_len_len - response_headers.size - 1) {
        result = io_error("HTTP response envelope is too large");
        goto cleanup;
    }

    size_t envelope_size =
        magic_len + (size_t)status_len + (size_t)header_len_len + response_headers.size + response.size;
    char *envelope = malloc(envelope_size + 1);
    if (envelope == NULL) {
        result = io_error("failed to allocate HTTP response envelope");
        goto cleanup;
    }
    size_t offset = 0;
    memcpy(envelope + offset, magic, magic_len);
    offset += magic_len;
    memcpy(envelope + offset, status_line, (size_t)status_len);
    offset += (size_t)status_len;
    memcpy(envelope + offset, header_len_line, (size_t)header_len_len);
    offset += (size_t)header_len_len;
    memcpy(envelope + offset, response_headers.data, response_headers.size);
    offset += response_headers.size;
    memcpy(envelope + offset, response.data, response.size);
    envelope[envelope_size] = 0;

    lean_object *lean_response = lean_mk_string(envelope);
    free(envelope);
    result = lean_io_result_mk_ok(lean_response);

cleanup:
    curl_slist_free_all(headers);
    free(auth_header);
    free(response_headers.data);
    free(response.data);
    curl_easy_cleanup(curl);
    return result;
}
