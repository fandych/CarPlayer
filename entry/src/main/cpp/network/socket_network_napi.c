#include <errno.h>
#include <net/if.h>
#include <netinet/in.h>
#include <napi/native_api.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>

static napi_value fail(napi_env env, const char *message)
{
    napi_throw_error(env, NULL, message);
    return NULL;
}

static napi_value fail_errno(napi_env env, const char *operation)
{
    char message[160];
    (void)snprintf(message, sizeof(message), "%s: %s", operation, strerror(errno));
    return fail(env, message);
}

static napi_value set_ipv6_socket_interface(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    int32_t socket_fd;
    char interface_name[IFNAMSIZ] = {0};
    size_t interface_name_length = 0;
    if (napi_get_cb_info(env, info, &argc, args, NULL, NULL) != napi_ok || argc != 2 ||
        napi_get_value_int32(env, args[0], &socket_fd) != napi_ok || socket_fd < 0 ||
        napi_get_value_string_utf8(env, args[1], interface_name, sizeof(interface_name),
            &interface_name_length) != napi_ok ||
        interface_name_length == 0 || interface_name_length >= sizeof(interface_name)) {
        return fail(env, "Invalid IPv6 socket interface arguments");
    }

    unsigned int interface_index = if_nametoindex(interface_name);
    if (interface_index == 0) {
        return fail_errno(env, "Unable to resolve IPv6 socket interface");
    }
    if (setsockopt(socket_fd, IPPROTO_IPV6, IPV6_UNICAST_IF, &interface_index,
            sizeof(interface_index)) != 0) {
        return fail_errno(env, "Unable to set IPv6 socket interface");
    }

    napi_value result;
    if (napi_get_undefined(env, &result) != napi_ok) {
        return fail(env, "Unable to return IPv6 socket interface result");
    }
    return result;
}

static napi_value init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"setIpv6SocketInterface", NULL, set_ipv6_socket_interface, NULL, NULL, NULL, napi_default, NULL}
    };
    if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) {
        return NULL;
    }
    return exports;
}

NAPI_MODULE(networkutils, init)
