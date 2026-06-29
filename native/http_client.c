#include <lean/lean.h>
#include <curl/curl.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/pem.h>
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

static int append_response_bytes(struct response_buffer *buffer, const void *data, size_t data_len) {
    if (data_len > buffer->limit - buffer->size) {
        buffer->too_large = 1;
        return 0;
    }
    if (buffer->size > SIZE_MAX - data_len - 1) {
        buffer->too_large = 1;
        return 0;
    }

    char *next = realloc(buffer->data, buffer->size + data_len + 1);
    if (next == NULL) {
        return 0;
    }

    buffer->data = next;
    memcpy(buffer->data + buffer->size, data, data_len);
    buffer->size += data_len;
    buffer->data[buffer->size] = 0;
    return 1;
}

static int append_response_cstr(struct response_buffer *buffer, const char *value) {
    return append_response_bytes(buffer, value, strlen(value));
}

static size_t write_response(void *contents, size_t size, size_t nmemb, void *userp) {
    if (size != 0 && nmemb > SIZE_MAX / size) {
        struct response_buffer *buffer = (struct response_buffer *)userp;
        buffer->too_large = 1;
        return 0;
    }

    size_t real_size = size * nmemb;
    struct response_buffer *buffer = (struct response_buffer *)userp;

    if (!append_response_bytes(buffer, contents, real_size)) {
        return 0;
    }
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

static char hex_digit_lower(unsigned char value) {
    value &= 0x0f;
    if (value < 10) {
        return (char)('0' + value);
    }
    return (char)('a' + (value - 10));
}

static char *hex_encode(const unsigned char *bytes, size_t len) {
    if (len > (SIZE_MAX - 1) / 2) {
        return NULL;
    }

    char *out = malloc(len * 2 + 1);
    if (out == NULL) {
        return NULL;
    }

    for (size_t i = 0; i < len; i++) {
        out[i * 2] = hex_digit_lower((unsigned char)(bytes[i] >> 4));
        out[i * 2 + 1] = hex_digit_lower(bytes[i]);
    }
    out[len * 2] = 0;
    return out;
}

static int hex_value(int c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return 10 + (c - 'a');
    }
    if (c >= 'A' && c <= 'F') {
        return 10 + (c - 'A');
    }
    return -1;
}

static unsigned char *hex_decode(const char *hex, size_t *out_len, const char **error_message) {
    size_t len = strlen(hex);
    if ((len & 1) != 0) {
        *error_message = "hex key length must be even";
        return NULL;
    }

    size_t bytes_len = len / 2;
    unsigned char *bytes = malloc(bytes_len == 0 ? 1 : bytes_len);
    if (bytes == NULL) {
        *error_message = "failed to allocate decoded hex bytes";
        return NULL;
    }

    for (size_t i = 0; i < bytes_len; i++) {
        int hi = hex_value((unsigned char)hex[i * 2]);
        int lo = hex_value((unsigned char)hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            free(bytes);
            *error_message = "hex key contained an invalid digit";
            return NULL;
        }
        bytes[i] = (unsigned char)((hi << 4) | lo);
    }

    *out_len = bytes_len;
    return bytes;
}

static lean_obj_res hmac_sha256_hex_result(
    const unsigned char *key,
    size_t key_len,
    const char *message
) {
    if (key_len > INT_MAX) {
        return io_error("HMAC key is too large");
    }

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    if (HMAC(
            EVP_sha256(),
            key,
            (int)key_len,
            (const unsigned char *)message,
            strlen(message),
            digest,
            &digest_len
        ) == NULL) {
        return io_error("failed to compute HMAC-SHA256");
    }

    char *encoded = hex_encode(digest, (size_t)digest_len);
    if (encoded == NULL) {
        return io_error("failed to encode HMAC-SHA256 digest");
    }

    lean_object *result = lean_mk_string(encoded);
    free(encoded);
    return lean_io_result_mk_ok(result);
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

lean_obj_res lean_agent_sign_jwt_rs256(
    lean_obj_arg lean_private_key_pem,
    lean_obj_arg lean_header_json,
    lean_obj_arg lean_payload_json
) {
    const char *private_key_pem = lean_string_cstr(lean_private_key_pem);
    const char *header_json = lean_string_cstr(lean_header_json);
    const char *payload_json = lean_string_cstr(lean_payload_json);

    char *header_b64 = base64url_encode((const unsigned char *)header_json, strlen(header_json));
    if (header_b64 == NULL) {
        return io_error("failed to encode JWT header");
    }

    char *payload_b64 = base64url_encode((const unsigned char *)payload_json, strlen(payload_json));
    if (payload_b64 == NULL) {
        free(header_b64);
        return io_error("failed to encode JWT payload");
    }

    size_t signing_input_len = strlen(header_b64) + 1 + strlen(payload_b64);
    char *signing_input = malloc(signing_input_len + 1);
    if (signing_input == NULL) {
        free(header_b64);
        free(payload_b64);
        return io_error("failed to allocate JWT signing input");
    }
    snprintf(signing_input, signing_input_len + 1, "%s.%s", header_b64, payload_b64);

    BIO *bio = BIO_new_mem_buf(private_key_pem, -1);
    if (bio == NULL) {
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to open private key buffer");
    }

    EVP_PKEY *pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (pkey == NULL) {
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to parse private key");
    }

    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (ctx == NULL) {
        EVP_PKEY_free(pkey);
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to allocate digest context");
    }

    if (EVP_DigestSignInit(ctx, NULL, EVP_sha256(), NULL, pkey) != 1) {
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(pkey);
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to initialize JWT signer");
    }

    if (EVP_DigestSignUpdate(ctx, signing_input, signing_input_len) != 1) {
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(pkey);
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to update JWT signer");
    }

    size_t signature_len = 0;
    if (EVP_DigestSignFinal(ctx, NULL, &signature_len) != 1) {
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(pkey);
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to size JWT signature");
    }

    unsigned char *signature = malloc(signature_len);
    if (signature == NULL) {
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(pkey);
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to allocate JWT signature");
    }

    if (EVP_DigestSignFinal(ctx, signature, &signature_len) != 1) {
        free(signature);
        EVP_MD_CTX_free(ctx);
        EVP_PKEY_free(pkey);
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to finalize JWT signature");
    }

    char *signature_b64 = base64url_encode(signature, signature_len);
    free(signature);
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    if (signature_b64 == NULL) {
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        return io_error("failed to encode JWT signature");
    }

    size_t jwt_len = signing_input_len + 1 + strlen(signature_b64);
    char *jwt = malloc(jwt_len + 1);
    if (jwt == NULL) {
        free(header_b64);
        free(payload_b64);
        free(signing_input);
        free(signature_b64);
        return io_error("failed to allocate JWT assertion");
    }
    snprintf(jwt, jwt_len + 1, "%s.%s", signing_input, signature_b64);

    lean_object *result = lean_mk_string(jwt);
    free(header_b64);
    free(payload_b64);
    free(signing_input);
    free(signature_b64);
    free(jwt);
    return lean_io_result_mk_ok(result);
}

lean_obj_res lean_agent_sha256_hex(lean_obj_arg lean_input) {
    const char *input = lean_string_cstr(lean_input);
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256((const unsigned char *)input, strlen(input), digest);

    char *encoded = hex_encode(digest, SHA256_DIGEST_LENGTH);
    if (encoded == NULL) {
        return io_error("failed to encode SHA256 digest");
    }

    lean_object *result = lean_mk_string(encoded);
    free(encoded);
    return lean_io_result_mk_ok(result);
}

lean_obj_res lean_agent_hmac_sha256_hex(
    lean_obj_arg lean_key,
    lean_obj_arg lean_message
) {
    const char *key = lean_string_cstr(lean_key);
    const char *message = lean_string_cstr(lean_message);
    return hmac_sha256_hex_result((const unsigned char *)key, strlen(key), message);
}

lean_obj_res lean_agent_hmac_sha256_hex_key_hex(
    lean_obj_arg lean_hex_key,
    lean_obj_arg lean_message
) {
    const char *hex_key = lean_string_cstr(lean_hex_key);
    const char *message = lean_string_cstr(lean_message);
    const char *decode_error = NULL;
    size_t key_len = 0;
    unsigned char *key = hex_decode(hex_key, &key_len, &decode_error);
    if (key == NULL) {
        return io_error(decode_error == NULL ? "failed to decode HMAC hex key" : decode_error);
    }

    lean_obj_res result = hmac_sha256_hex_result(key, key_len, message);
    free(key);
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

static uint16_t read_be_u16(const unsigned char *bytes) {
    return (uint16_t)(((uint16_t)bytes[0] << 8) | (uint16_t)bytes[1]);
}

static uint32_t read_be_u32(const unsigned char *bytes) {
    return
        ((uint32_t)bytes[0] << 24) |
        ((uint32_t)bytes[1] << 16) |
        ((uint32_t)bytes[2] << 8) |
        (uint32_t)bytes[3];
}

struct aws_eventstream_headers {
    char *message_type;
    char *event_type;
    char *exception_type;
};

static void free_aws_eventstream_headers(struct aws_eventstream_headers *headers) {
    free(headers->message_type);
    free(headers->event_type);
    free(headers->exception_type);
    headers->message_type = NULL;
    headers->event_type = NULL;
    headers->exception_type = NULL;
}

static char *copy_bytes_to_cstring(const unsigned char *bytes, size_t len) {
    char *copy = malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, bytes, len);
    copy[len] = 0;
    return copy;
}

static int eventstream_header_name_matches(
    const unsigned char *name,
    size_t name_len,
    const char *expected
) {
    size_t expected_len = strlen(expected);
    return name_len == expected_len && memcmp(name, expected, expected_len) == 0;
}

static int skip_aws_eventstream_header_value(
    uint8_t value_type,
    const unsigned char *bytes,
    size_t size,
    size_t *offset,
    const char **error_message
) {
    size_t next = *offset;
    switch (value_type) {
        case 0:
        case 1:
            break;
        case 2:
            if (size - next < 1) {
                *error_message = "AWS event-stream byte header was truncated";
                return 0;
            }
            next += 1;
            break;
        case 3:
            if (size - next < 2) {
                *error_message = "AWS event-stream short header was truncated";
                return 0;
            }
            next += 2;
            break;
        case 4:
            if (size - next < 4) {
                *error_message = "AWS event-stream int header was truncated";
                return 0;
            }
            next += 4;
            break;
        case 5:
        case 8:
            if (size - next < 8) {
                *error_message = "AWS event-stream long header was truncated";
                return 0;
            }
            next += 8;
            break;
        case 6:
        case 7: {
            if (size - next < 2) {
                *error_message = "AWS event-stream variable-length header was truncated";
                return 0;
            }
            uint16_t value_len = read_be_u16(bytes + next);
            next += 2;
            if (size - next < value_len) {
                *error_message = "AWS event-stream variable-length header value was truncated";
                return 0;
            }
            next += value_len;
            break;
        }
        case 9:
            if (size - next < 16) {
                *error_message = "AWS event-stream UUID header was truncated";
                return 0;
            }
            next += 16;
            break;
        default:
            *error_message = "AWS event-stream header used an unsupported value type";
            return 0;
    }
    *offset = next;
    return 1;
}

static int capture_aws_eventstream_string_header(
    char **target,
    const unsigned char *bytes,
    size_t size,
    size_t *offset,
    const char **error_message
) {
    if (size - *offset < 2) {
        *error_message = "AWS event-stream string header length was truncated";
        return 0;
    }
    uint16_t value_len = read_be_u16(bytes + *offset);
    *offset += 2;
    if (size - *offset < value_len) {
        *error_message = "AWS event-stream string header value was truncated";
        return 0;
    }
    char *value = copy_bytes_to_cstring(bytes + *offset, value_len);
    if (value == NULL) {
        *error_message = "failed to allocate AWS event-stream header string";
        return 0;
    }
    free(*target);
    *target = value;
    *offset += value_len;
    return 1;
}

static int parse_aws_eventstream_headers(
    const unsigned char *bytes,
    size_t size,
    struct aws_eventstream_headers *headers,
    const char **error_message
) {
    size_t offset = 0;
    while (offset < size) {
        if (size - offset < 2) {
            *error_message = "AWS event-stream header entry was truncated";
            return 0;
        }
        uint8_t name_len = bytes[offset++];
        if (size - offset < name_len + 1) {
            *error_message = "AWS event-stream header name was truncated";
            return 0;
        }
        const unsigned char *name = bytes + offset;
        offset += name_len;
        uint8_t value_type = bytes[offset++];
        if (eventstream_header_name_matches(name, name_len, ":message-type") && value_type == 7) {
            if (!capture_aws_eventstream_string_header(&headers->message_type, bytes, size, &offset, error_message)) {
                return 0;
            }
        } else if (eventstream_header_name_matches(name, name_len, ":event-type") && value_type == 7) {
            if (!capture_aws_eventstream_string_header(&headers->event_type, bytes, size, &offset, error_message)) {
                return 0;
            }
        } else if (eventstream_header_name_matches(name, name_len, ":exception-type") && value_type == 7) {
            if (!capture_aws_eventstream_string_header(&headers->exception_type, bytes, size, &offset, error_message)) {
                return 0;
            }
        } else {
            if (!skip_aws_eventstream_header_value(value_type, bytes, size, &offset, error_message)) {
                return 0;
            }
        }
    }
    return 1;
}

static int append_json_escaped_bytes(
    struct response_buffer *buffer,
    const unsigned char *bytes,
    size_t len
) {
    static const char hex[] = "0123456789abcdef";
    if (!append_response_bytes(buffer, "\"", 1)) {
        return 0;
    }
    for (size_t i = 0; i < len; i++) {
        unsigned char byte = bytes[i];
        switch (byte) {
            case '"':
                if (!append_response_bytes(buffer, "\\\"", 2)) {
                    return 0;
                }
                break;
            case '\\':
                if (!append_response_bytes(buffer, "\\\\", 2)) {
                    return 0;
                }
                break;
            case '\b':
                if (!append_response_bytes(buffer, "\\b", 2)) {
                    return 0;
                }
                break;
            case '\f':
                if (!append_response_bytes(buffer, "\\f", 2)) {
                    return 0;
                }
                break;
            case '\n':
                if (!append_response_bytes(buffer, "\\n", 2)) {
                    return 0;
                }
                break;
            case '\r':
                if (!append_response_bytes(buffer, "\\r", 2)) {
                    return 0;
                }
                break;
            case '\t':
                if (!append_response_bytes(buffer, "\\t", 2)) {
                    return 0;
                }
                break;
            default:
                if (byte < 0x20) {
                    char encoded[6] = { '\\', 'u', '0', '0', hex[byte >> 4], hex[byte & 0x0f] };
                    if (!append_response_bytes(buffer, encoded, sizeof(encoded))) {
                        return 0;
                    }
                } else {
                    if (!append_response_bytes(buffer, &byte, 1)) {
                        return 0;
                    }
                }
                break;
        }
    }
    return append_response_bytes(buffer, "\"", 1);
}

static const unsigned char *skip_ascii_whitespace(const unsigned char *bytes, size_t size, size_t *skipped) {
    size_t offset = 0;
    while (offset < size) {
        unsigned char byte = bytes[offset];
        if (byte != ' ' && byte != '\n' && byte != '\r' && byte != '\t') {
            break;
        }
        offset++;
    }
    *skipped = offset;
    return bytes + offset;
}

static int append_json_payload_value(
    struct response_buffer *buffer,
    const unsigned char *bytes,
    size_t len
) {
    size_t skipped = 0;
    const unsigned char *trimmed = skip_ascii_whitespace(bytes, len, &skipped);
    size_t trimmed_len = len - skipped;
    if (trimmed_len == 0) {
        return append_response_cstr(buffer, "{}");
    }

    unsigned char first = trimmed[0];
    if (
        first == '{' || first == '[' || first == '"' ||
        first == 't' || first == 'f' || first == 'n' ||
        first == '-' || (first >= '0' && first <= '9')
    ) {
        return append_response_bytes(buffer, trimmed, trimmed_len);
    }

    return append_json_escaped_bytes(buffer, trimmed, trimmed_len);
}

static int normalize_aws_eventstream_body(
    const unsigned char *bytes,
    size_t size,
    struct response_buffer *out,
    const char **error_message
) {
    if (!append_response_bytes(out, "[", 1)) {
        *error_message = "failed to allocate normalized AWS event-stream body";
        return 0;
    }

    size_t offset = 0;
    int first = 1;
    while (offset < size) {
        if (size - offset < 16) {
            *error_message = "AWS event-stream frame was truncated";
            return 0;
        }
        uint32_t total_len = read_be_u32(bytes + offset);
        uint32_t headers_len = read_be_u32(bytes + offset + 4);
        if (total_len < 16) {
            *error_message = "AWS event-stream frame total length was too small";
            return 0;
        }
        if ((uint64_t)total_len > (uint64_t)(size - offset)) {
            *error_message = "AWS event-stream frame exceeded response length";
            return 0;
        }
        if (headers_len > total_len - 16) {
            *error_message = "AWS event-stream frame header length was invalid";
            return 0;
        }

        const unsigned char *frame = bytes + offset;
        const unsigned char *header_bytes = frame + 12;
        const unsigned char *payload_bytes = header_bytes + headers_len;
        size_t payload_len = (size_t)total_len - (size_t)headers_len - 16;

        struct aws_eventstream_headers headers = { 0 };
        if (!parse_aws_eventstream_headers(header_bytes, headers_len, &headers, error_message)) {
            free_aws_eventstream_headers(&headers);
            return 0;
        }

        const char *event_key = headers.event_type;
        if (event_key == NULL || event_key[0] == 0) {
            event_key = headers.exception_type;
        }
        if (event_key == NULL || event_key[0] == 0) {
            event_key = headers.message_type;
        }
        if (event_key == NULL || event_key[0] == 0) {
            event_key = "payload";
        }

        if (!first && !append_response_bytes(out, ",", 1)) {
            free_aws_eventstream_headers(&headers);
            *error_message = "failed to allocate normalized AWS event-stream separator";
            return 0;
        }
        first = 0;

        if (
            !append_response_bytes(out, "{", 1) ||
            !append_json_escaped_bytes(out, (const unsigned char *)event_key, strlen(event_key)) ||
            !append_response_bytes(out, ":", 1) ||
            !append_json_payload_value(out, payload_bytes, payload_len) ||
            !append_response_bytes(out, "}", 1)
        ) {
            free_aws_eventstream_headers(&headers);
            *error_message = "failed to allocate normalized AWS event-stream item";
            return 0;
        }

        free_aws_eventstream_headers(&headers);
        offset += total_len;
    }

    if (!append_response_bytes(out, "]", 1)) {
        *error_message = "failed to finalize normalized AWS event-stream body";
        return 0;
    }
    return 1;
}

static int body_looks_like_json_text(const unsigned char *bytes, size_t size) {
    size_t skipped = 0;
    const unsigned char *trimmed = skip_ascii_whitespace(bytes, size, &skipped);
    size_t trimmed_len = size - skipped;
    if (trimmed_len == 0) {
        return 1;
    }

    unsigned char first = trimmed[0];
    return
        first == '{' || first == '[' || first == '"' ||
        first == 't' || first == 'f' || first == 'n' ||
        first == '-' || (first >= '0' && first <= '9');
}

static lean_obj_res build_http_envelope(
    long status_code,
    const struct response_buffer *response_headers,
    const char *body,
    size_t body_size
) {
    const char *magic = "LAHTTP2\n";
    size_t magic_len = strlen(magic);
    char status_line[32];
    int status_len = snprintf(status_line, sizeof(status_line), "%ld\n", status_code);
    if (status_len < 0 || (size_t)status_len >= sizeof(status_line)) {
        return io_error("failed to format HTTP status");
    }
    char header_len_line[32];
    int header_len_len = snprintf(header_len_line, sizeof(header_len_line), "%zu\n", response_headers->size);
    if (header_len_len < 0 || (size_t)header_len_len >= sizeof(header_len_line)) {
        return io_error("failed to format HTTP header length");
    }
    if (body_size > SIZE_MAX - magic_len - (size_t)status_len - (size_t)header_len_len - response_headers->size - 1) {
        return io_error("HTTP response envelope is too large");
    }

    size_t envelope_size =
        magic_len + (size_t)status_len + (size_t)header_len_len + response_headers->size + body_size;
    char *envelope = malloc(envelope_size + 1);
    if (envelope == NULL) {
        return io_error("failed to allocate HTTP response envelope");
    }
    size_t next = 0;
    memcpy(envelope + next, magic, magic_len);
    next += magic_len;
    memcpy(envelope + next, status_line, (size_t)status_len);
    next += (size_t)status_len;
    memcpy(envelope + next, header_len_line, (size_t)header_len_len);
    next += (size_t)header_len_len;
    memcpy(envelope + next, response_headers->data, response_headers->size);
    next += response_headers->size;
    memcpy(envelope + next, body, body_size);
    envelope[envelope_size] = 0;

    lean_object *lean_response = lean_mk_string(envelope);
    free(envelope);
    return lean_io_result_mk_ok(lean_response);
}

#define SETOPT_OR_GOTO(option, value) do { \
    CURLcode opt_code = curl_easy_setopt(curl, option, value); \
    if (opt_code != CURLE_OK) { \
        result = io_errorf("curl_easy_setopt " #option " failed", curl_easy_strerror(opt_code)); \
        goto cleanup; \
    } \
} while (0)

static lean_obj_res lean_agent_http_request_core(
    lean_obj_arg lean_method,
    lean_obj_arg lean_url,
    lean_obj_arg lean_authorization,
    lean_obj_arg lean_body,
    lean_obj_arg lean_no_proxy,
    lean_obj_arg lean_user_agent,
    lean_obj_arg lean_extra_headers,
    uint32_t timeout_seconds,
    uint32_t connect_timeout_seconds,
    uint64_t max_response_bytes,
    int normalize_eventstream
) {
    const char *method = lean_string_cstr(lean_method);
    const char *url = lean_string_cstr(lean_url);
    const char *authorization = lean_string_cstr(lean_authorization);
    const char *body = lean_string_cstr(lean_body);
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

    size_t body_len = strlen(body);
    if (body_len > LONG_MAX) {
        return io_error("request body is too large");
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

    struct response_buffer normalized;
    normalized.data = NULL;
    normalized.size = 0;
    normalized.limit = 0;
    normalized.too_large = 0;

    char error_buffer[CURL_ERROR_SIZE];
    error_buffer[0] = 0;

    char *auth_header = NULL;
    struct curl_slist *headers = NULL;
    if (!header_block_has(extra_headers, "Authorization") && authorization[0] != 0) {
        size_t auth_prefix_len = strlen("Authorization: ");
        size_t value_len = strlen(authorization);
        auth_header = malloc(auth_prefix_len + value_len + 1);
        if (auth_header == NULL) {
            result = io_error("failed to allocate authorization header");
            goto cleanup;
        }
        memcpy(auth_header, "Authorization: ", auth_prefix_len);
        memcpy(auth_header + auth_prefix_len, authorization, value_len);
        auth_header[auth_prefix_len + value_len] = 0;
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
    SETOPT_OR_GOTO(CURLOPT_CUSTOMREQUEST, method);
    if (body_len > 0 || strcmp(method, "POST") == 0 || strcmp(method, "PUT") == 0 || strcmp(method, "PATCH") == 0) {
        SETOPT_OR_GOTO(CURLOPT_POSTFIELDS, body);
        SETOPT_OR_GOTO(CURLOPT_POSTFIELDSIZE, (long)body_len);
    }
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
    const char *response_body = response.data;
    size_t body_size = response.size;
    if (
        normalize_eventstream &&
        status_code >= 200 &&
        status_code < 300 &&
        !body_looks_like_json_text((const unsigned char *)response.data, response.size)
    ) {
        normalized.limit =
            response.size > (SIZE_MAX - 4096) / 6
                ? SIZE_MAX
                : response.size * 6 + 4096;
        normalized.data = malloc(1);
        if (normalized.data == NULL) {
            result = io_error("failed to allocate normalized AWS event-stream buffer");
            goto cleanup;
        }
        normalized.data[0] = 0;

        const char *normalize_error = NULL;
        if (
            !normalize_aws_eventstream_body(
                (const unsigned char *)response.data,
                response.size,
                &normalized,
                &normalize_error
            )
        ) {
            if (normalized.too_large) {
                result = io_error("normalized AWS event-stream response exceeded internal buffer");
            } else {
                result = io_error(
                    normalize_error == NULL
                        ? "failed to decode AWS event-stream response"
                        : normalize_error
                );
            }
            goto cleanup;
        }
        response_body = normalized.data;
        body_size = normalized.size;
    }

    result = build_http_envelope(status_code, &response_headers, response_body, body_size);

cleanup:
    curl_slist_free_all(headers);
    free(auth_header);
    free(normalized.data);
    free(response_headers.data);
    free(response.data);
    curl_easy_cleanup(curl);
    return result;
}

lean_obj_res lean_agent_http_request(
    lean_obj_arg lean_method,
    lean_obj_arg lean_url,
    lean_obj_arg lean_authorization,
    lean_obj_arg lean_body,
    lean_obj_arg lean_no_proxy,
    lean_obj_arg lean_user_agent,
    lean_obj_arg lean_extra_headers,
    uint32_t timeout_seconds,
    uint32_t connect_timeout_seconds,
    uint64_t max_response_bytes
) {
    return lean_agent_http_request_core(
        lean_method,
        lean_url,
        lean_authorization,
        lean_body,
        lean_no_proxy,
        lean_user_agent,
        lean_extra_headers,
        timeout_seconds,
        connect_timeout_seconds,
        max_response_bytes,
        0
    );
}

lean_obj_res lean_agent_http_request_aws_eventstream_json(
    lean_obj_arg lean_method,
    lean_obj_arg lean_url,
    lean_obj_arg lean_authorization,
    lean_obj_arg lean_body,
    lean_obj_arg lean_no_proxy,
    lean_obj_arg lean_user_agent,
    lean_obj_arg lean_extra_headers,
    uint32_t timeout_seconds,
    uint32_t connect_timeout_seconds,
    uint64_t max_response_bytes
) {
    return lean_agent_http_request_core(
        lean_method,
        lean_url,
        lean_authorization,
        lean_body,
        lean_no_proxy,
        lean_user_agent,
        lean_extra_headers,
        timeout_seconds,
        connect_timeout_seconds,
        max_response_bytes,
        1
    );
}

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
    lean_object *method = lean_mk_string("POST");
    size_t auth_prefix_len = strlen("Bearer ");
    const char *api_key = lean_string_cstr(lean_api_key);
    size_t key_len = strlen(api_key);
    char *authorization = malloc(auth_prefix_len + key_len + 1);
    if (authorization == NULL) {
        lean_dec(method);
        return io_error("failed to allocate authorization header");
    }
    memcpy(authorization, "Bearer ", auth_prefix_len);
    memcpy(authorization + auth_prefix_len, api_key, key_len);
    authorization[auth_prefix_len + key_len] = 0;
    lean_object *lean_authorization = lean_mk_string(authorization);
    free(authorization);
    lean_obj_res result = lean_agent_http_request(
        method,
        lean_url,
        lean_authorization,
        lean_payload,
        lean_no_proxy,
        lean_user_agent,
        lean_extra_headers,
        timeout_seconds,
        connect_timeout_seconds,
        max_response_bytes
    );
    lean_dec(method);
    lean_dec(lean_authorization);
    return result;
}
