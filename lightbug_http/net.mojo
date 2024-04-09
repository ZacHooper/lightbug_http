from lightbug_http.strings import NetworkType
from lightbug_http.io.bytes import Bytes
from lightbug_http.io.sync import Duration
from lightbug_http.sys.net import SysConnection
from external.libc import (
    AF_INET,
    SOCK_STREAM,
    AI_PASSIVE,
    c_int,
    c_char,
    in_addr,
    addrinfo,
    sockaddr_in,
    getaddrinfo,
    gai_strerror,
    to_char_ptr,
    c_charptr_to_string,
)

alias default_buffer_size = 4096
alias default_tcp_keep_alive = Duration(15 * 1000 * 1000 * 1000)  # 15 seconds


trait Net(DefaultConstructible):
    fn __init__(inout self):
        ...

    fn __init__(inout self, keep_alive: Duration) raises:
        ...

    # A listen method should be implemented on structs that implement Net.
    # Signature is not enforced for now.
    # fn listen(inout self, network: String, addr: String) raises -> Listener:
    #    ...


trait ListenConfig:
    fn __init__(inout self, keep_alive: Duration) raises:
        ...

    # A listen method should be implemented on structs that implement ListenConfig.
    # Signature is not enforced for now.
    # fn listen(inout self, network: String, address: String) raises -> Listener:
    #    ...


trait Listener(Movable):
    fn __init__(inout self) raises:
        ...

    fn __init__(inout self, addr: TCPAddr) raises:
        ...

    fn accept(borrowed self) raises -> SysConnection:
        ...

    fn close(self) raises:
        ...

    fn addr(self) -> TCPAddr:
        ...


trait Connection(Movable):
    fn __init__(inout self, laddr: String, raddr: String) raises:
        ...

    fn __init__(inout self, laddr: TCPAddr, raddr: TCPAddr) raises:
        ...

    fn read(self, inout buf: Bytes) raises -> Int:
        ...

    fn write(self, buf: Bytes) raises -> Int:
        ...

    fn close(self) raises:
        ...

    fn local_addr(inout self) raises -> TCPAddr:
        ...

    fn remote_addr(self) raises -> TCPAddr:
        ...


trait Addr(CollectionElement):
    fn __init__(inout self):
        ...

    fn __init__(inout self, ip: String, port: Int):
        ...

    fn network(self) -> String:
        ...

    fn string(self) -> String:
        ...


alias TCPAddrList = List[TCPAddr]


@value
struct TCPAddr(Addr):
    var ip: String
    var port: Int
    var zone: String  # IPv6 addressing zone

    fn __init__(inout self):
        self.ip = String("127.0.0.1")
        self.port = 8000
        self.zone = ""

    fn __init__(inout self, ip: String, port: Int):
        self.ip = ip
        self.port = port
        self.zone = ""

    fn network(self) -> String:
        return NetworkType.tcp.value

    fn string(self) -> String:
        if self.zone != "":
            return join_host_port(String(self.ip) + "%" + self.zone, self.port)
        return join_host_port(self.ip, self.port)


fn resolve_internet_addr(network: String, address: String) raises -> TCPAddr:
    var host: String = ""
    var port: String = ""
    var portnum: Int = 0
    if (
        network == NetworkType.tcp.value
        or network == NetworkType.tcp4.value
        or network == NetworkType.tcp6.value
        or network == NetworkType.udp.value
        or network == NetworkType.udp4.value
        or network == NetworkType.udp6.value
    ):
        if address != "":
            var host_port = split_host_port(address)
            host = host_port.host
            port = host_port.port
            portnum = atol(port.__str__())
    elif (
        network == NetworkType.ip.value
        or network == NetworkType.ip4.value
        or network == NetworkType.ip6.value
    ):
        if address != "":
            host = address
    elif network == NetworkType.unix.value:
        raise Error("Unix addresses not supported yet")
    else:
        raise Error("unsupported network type: " + network)
    return TCPAddr(host, portnum)


fn join_host_port(host: String, port: String) -> String:
    if host.find(":") != -1:  # must be IPv6 literal
        return "[" + host + "]:" + port
    return host + ":" + port


alias missingPortError = Error("missing port in address")
alias tooManyColonsError = Error("too many colons in address")


struct HostPort:
    var host: String
    var port: String

    fn __init__(inout self, host: String, port: String):
        self.host = host
        self.port = port


fn split_host_port(hostport: String) raises -> HostPort:
    var host: String = ""
    var port: String = ""
    var colon_index = hostport.rfind(":")
    var j: Int = 0
    var k: Int = 0

    if colon_index == -1:
        raise missingPortError
    if hostport[0] == "[":
        var end_bracket_index = hostport.find("]")
        if end_bracket_index == -1:
            raise Error("missing ']' in address")
        if end_bracket_index + 1 == len(hostport):
            raise missingPortError
        elif end_bracket_index + 1 == colon_index:
            host = hostport[1:end_bracket_index]
            j = 1
            k = end_bracket_index + 1
        else:
            if hostport[end_bracket_index + 1] == ":":
                raise tooManyColonsError
            else:
                raise missingPortError
    else:
        host = hostport[:colon_index]
        if host.find(":") != -1:
            raise tooManyColonsError
    if hostport[j:].find("[") != -1:
        raise Error("unexpected '[' in address")
    if hostport[k:].find("]") != -1:
        raise Error("unexpected ']' in address")
    port = hostport[colon_index + 1 :]

    if port == "":
        raise missingPortError
    if host == "":
        raise Error("missing host")
    return HostPort(host, port)


fn get_addr_info(host: String) raises -> addrinfo:
    var servinfo = Pointer[addrinfo]().alloc(1)
    servinfo.store(addrinfo())

    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_STREAM
    hints.ai_flags = AI_PASSIVE

    var host_ptr = to_char_ptr(host)

    var status = getaddrinfo(
        host_ptr,
        Pointer[UInt8](),
        Pointer.address_of(hints),
        Pointer.address_of(servinfo),
    )
    if status != 0:
        print("getaddrinfo failed to execute with status:", status)
        var msg_ptr = gai_strerror(c_int(status))
        _ = external_call["printf", c_int, Pointer[c_char], Pointer[c_char]](
            to_char_ptr("gai_strerror: %s"), msg_ptr
        )
        var msg = c_charptr_to_string(msg_ptr)
        print("getaddrinfo error message: ", msg)

    if not servinfo:
        print("servinfo is null")
        raise Error("Failed to get address info. Pointer to addrinfo is null.")

    return servinfo.load()


fn get_ip_address(host: String) raises -> in_addr:
    """Get the IP address of a host as binary."""
    # Call getaddrinfo to get the IP address of the host.
    var addrinfo = get_addr_info(host)
    var ai_addr = addrinfo.ai_addr
    if not ai_addr:
        print("ai_addr is null")
        raise Error(
            "Failed to get IP address. getaddrinfo was called successfully, but ai_addr"
            " is null."
        )

    # Cast sockaddr struct to sockaddr_in struct and convert the binary IP to a string using inet_ntop.
    var addr_in = ai_addr.bitcast[sockaddr_in]().load()

    return addr_in.sin_addr
