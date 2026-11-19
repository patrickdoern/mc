#include <curl/curl.h>

// Swift kann die variadische curl_easy_setopt nicht aufrufen, daher diese Hüllen.
static inline CURLcode mc_curl_setopt_long(CURL *handle, CURLoption option, long value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode mc_curl_setopt_string(CURL *handle, CURLoption option, const char *value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode mc_curl_setopt_pointer(CURL *handle, CURLoption option, void *value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode mc_curl_setopt_slist(CURL *handle, CURLoption option, struct curl_slist *value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode mc_curl_setopt_offset(CURL *handle, CURLoption option, curl_off_t value) {
    return curl_easy_setopt(handle, option, value);
}

static inline CURLcode mc_curl_setopt_write(CURL *handle, curl_write_callback callback, void *data) {
    CURLcode code = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, callback);
    return code != CURLE_OK ? code : curl_easy_setopt(handle, CURLOPT_WRITEDATA, data);
}

static inline CURLcode mc_curl_setopt_read(CURL *handle, curl_read_callback callback, void *data) {
    CURLcode code = curl_easy_setopt(handle, CURLOPT_READFUNCTION, callback);
    return code != CURLE_OK ? code : curl_easy_setopt(handle, CURLOPT_READDATA, data);
}

static inline long mc_curl_response_code(CURL *handle) {
    long code = 0;
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &code);
    return code;
}
