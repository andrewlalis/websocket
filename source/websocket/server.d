module websocket.server;

/**
 * Creates the required SHA-1, Base-64 encoded "Sec-WebSocket-Accept" header
 * value using the key provided by the client in "Sec-WebSocket-Key".
 * Params:
 *   key = The client's key.
 * Returns: The header string to use.
 */
string createSecWebSocketAcceptHeader(string key) {
    import std.digest.sha : sha1Of;
    import std.base64;
    ubyte[20] hash = sha1Of(key ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    return Base64.encode(hash);
}

version (Have_handy_httpd) {

/**
 * A special HttpRequestHandler implementation that exclusively handles
 * websocket connection handshakes.
 */
class WebSocketHandler : HttpRequestHandler {
    import handy_httpd.components.request : Method;
    import handy_httpd.components.response : HttpStatus;

    private WebSocketMessageHandler messageHandler;

    /**
     * Constructs the websocket handler using the given message handler for
     * any websocket messages received via this handler.
     * Params:
     *   messageHandler = The message handler to use.
     */
    this(WebSocketMessageHandler messageHandler) {
        this.messageHandler = messageHandler;
    }

    /**
     * Handles an HTTP request by verifying that it's a legitimate websocket
     * request, then sends a 101 SWITCHING PROTOCOLS response, and finally,
     * registers a new websocket connection with the server's manager. If an
     * invalid request is given, then a client error response code will be
     * sent back.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequestContext ctx) {
        if (!this.verifyRequest(ctx)) return;
        this.sendSwitchingProtocolsResponse(ctx);
        ctx.server.getWebSocketManager().registerConnection(ctx.clientSocket, this.messageHandler);
    }

    /**
     * Verifies a websocket request.
     * Params:
     *   ctx = The request context to verify.
     * Returns: True if the request is valid can a websocket connection can be
     * created, or false if we should reject. A response message will already
     * be written in that case.
     */
    private bool verifyRequest(ref HttpRequestContext ctx) {
        string origin = ctx.request.headers.getFirst("origin").orElse(null);
        // TODO: Verify correct origin.
        if (ctx.request.method != Method.GET) {
            ctx.response.setStatus(HttpStatus.METHOD_NOT_ALLOWED);
            ctx.response.writeBodyString("Only GET requests are allowed.");
            return false;
        }
        string key = ctx.request.headers.getFirst("Sec-WebSocket-Key").orElse(null);
        if (key is null) {
            ctx.response.setStatus(HttpStatus.BAD_REQUEST);
            ctx.response.writeBodyString("Missing Sec-WebSocket-Key header.");
            return false;
        }
        if (!ctx.server.config.enableWebSockets) {
            ctx.response.setStatus(HttpStatus.SERVICE_UNAVAILABLE);
            ctx.response.writeBodyString("This server does not support websockets.");
            return false;
        }
        return true;
    }

    /**
     * Sends an HTTP 101 SWITCHING PROTOCOLS response to a client, to indicate
     * that we'll be switching to the websocket protocol for all future
     * communications.
     * Params:
     *   ctx = The request context to send the response to.
     */
    private void sendSwitchingProtocolsResponse(ref HttpRequestContext ctx) {
        string key = ctx.request.headers.getFirst("Sec-WebSocket-Key").orElseThrow();
        ctx.response.setStatus(HttpStatus.SWITCHING_PROTOCOLS);
        ctx.response.addHeader("Upgrade", "websocket");
        ctx.response.addHeader("Connection", "Upgrade");
        ctx.response.addHeader("Sec-WebSocket-Accept", createSecWebSocketAcceptHeader(key));
        ctx.response.flushHeaders();
    }
}

} else {}