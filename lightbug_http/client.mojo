from lightbug_http.http import HTTPRequest, HTTPResponse
from lightbug_http.net import SysConnection, TCPAddr
from lightbug_http.io.bytes import Bytes
from lightbug_http.sys.net import create_connection
from external.libc import socket, AF_INET, SOCK_STREAM, c_int


trait Client:
    fn __init__(inout self) raises:
        ...

    fn __init__(inout self, host: StringLiteral, port: Int) raises:
        ...

    fn do(self, req: HTTPRequest) raises -> HTTPResponse:
        ...


struct HTTPClient(Client):
    var host: StringLiteral
    var port: Int
    var sock: c_int

    fn __init__(inout self) raises:
        self.host = "localhost"
        self.port = 80
        self.sock = socket(AF_INET, SOCK_STREAM, 0)

    fn __init__(inout self, host: StringLiteral, port: Int) raises:
        self.host = host
        self.port = port
        self.sock = socket(AF_INET, SOCK_STREAM, 0)

    fn do(self, req: HTTPRequest) raises -> HTTPResponse:
        """
        The `do` method is responsible for sending an HTTP request to a server and receiving the corresponding response.

        It performs the following steps:
        1. Creates a connection to the server specified in the request.
        2. Sends the request body using the connection.
        3. Receives the response from the server.
        4. Closes the connection.
        5. Returns the received response as an `HTTPResponse` object.

        Note: The code assumes that the `HTTPRequest` object passed as an argument has a valid URI with a host and port specified.

        Parameters
        ----------
        req : HTTPRequest :
            An `HTTPRequest` object representing the request to be sent.

        Returns
        -------
        HTTPResponse :
            The received response.

        Raises
        ------
        Error :
            If there is a failure in sending or receiving the message.

        Examples
        --------
        ```mojo
        client = HTTPClient()
        request = HTTPRequest(...)
        response = client.do(request)
        ```
        """
        # Create a connection to the server of the request
        var uri = req.uri()
        _ = uri.parse()
        var host_port = String(uri.host()).split(":")
        var host = host_port[0]
        var port = atol(host_port[1])
        var conn = create_connection(self.sock, host, port)

        # Send the request
        print("Sending message...")
        var bytes_sent = conn.write(req.get_body())
        if bytes_sent == -1:
            raise Error("Failed to send message")

        # Receive the response
        var response: String = ""
        var buf_2 = Bytes()
        while True:
            var bytes_recv = conn.read(buf_2)
            if bytes_recv == -1:
                raise Error("Failed to receive message")
            elif bytes_recv == 0:
                break
            else:
                response += String(buf_2)

        conn.close()

        return HTTPResponse(response._buffer)
