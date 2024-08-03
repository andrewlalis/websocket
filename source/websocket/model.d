/**
 * This module defines websocket message types, the connection, and message
 * handler.
 */
module websocket.model;

import slf4d;

/**
 * An exception that's thrown if an unexpected situation arises while dealing
 * with a websocket connection.
 */
class WebSocketException : Exception {
    import std.exception : basicExceptionCtors;
    mixin basicExceptionCtors;
}

/**
 * A text-based websocket message.
 */
struct WebSocketTextMessage {
    /// The connection that this message is bound to.
    WebSocketConnection conn;
    /// The textual content of the message.
    string payload;
}

/**
 * A binary websocket message.
 */
struct WebSocketBinaryMessage {
    /// The connection that this message is bound to.
    WebSocketConnection conn;
    /// The binary content of the message.
    ubyte[] payload;
}

/**
 * A "close" control websocket message indicating the client is closing the
 * connection.
 */
struct WebSocketCloseMessage {
    /// The connection that this message is bound to.
    WebSocketConnection conn;
    /// The status code of the close message. See `websocket.frame : WebSocketCloseStatusCode`.
    ushort statusCode;
    /// The message sent with this close message. This may be null.
    string message;
}

/**
 * All the data that represents a WebSocket connection.
 */
class WebSocketConnection {
    import std.uuid : UUID, randomUUID;
    import std.socket : Socket, SocketShutdown;
    import streams : SocketOutputStream, byteArrayOutputStream, dataOutputStreamFor;

    import websocket.frame;

    /// The internal ID for this connection.
    immutable UUID id;

    /// The underlying socket on which data frames are sent and received.
    Socket socket;

    /// The message handler that'll be called for events pertaining to this connection.
    private WebSocketMessageHandler messageHandler;

    this(Socket socket, WebSocketMessageHandler messageHandler) {
        this.socket = socket;
        this.messageHandler = messageHandler;
        this.id = randomUUID();
    }

    Socket getSocket() {
        return this.socket;
    }

    WebSocketMessageHandler getMessageHandler() {
        return this.messageHandler;
    }

    /**
     * Sends a text message to the connected client.
     * Params:
     *   text = The text to send. Should be valid UTF-8.
     */
    void sendTextMessage(string text) {
        throwIfClosed();
        sendWebSocketTextFrame(SocketOutputStream(this.socket), text);
    }

    /**
     * Sends a binary message to the connected client.
     * Params:
     *   bytes = The binary data to send.
     */
    void sendBinaryMessage(ubyte[] bytes) {
        throwIfClosed();
        sendWebSocketBinaryFrame(SocketOutputStream(this.socket), bytes);
    }

    /**
     * Sends a close message to the client, indicating that we'll be closing
     * the connection.
     * Params:
     *   status = The status code for closing.
     *   message = A message explaining why we're closing. Length must be <= 123.
     */
    void sendCloseMessage(WebSocketCloseStatusCode status, string message) {
        throwIfClosed();
        sendWebSocketCloseFrame(SocketOutputStream(this.socket), status, message);
    }

    /**
     * Helper method to throw a WebSocketException if our socket is no longer
     * alive, so we know right away if the connection stopped abruptly.
     */
    private void throwIfClosed() {
        if (!this.socket.isAlive()) {
            throw new WebSocketException("Connection " ~ this.id.toString() ~ "'s socket is closed.");
        }
    }

    /**
     * Closes this connection, if it's alive, sending a websocket close message.
     */
    void close() {
        if (this.socket.isAlive()) {
            try {
                this.sendCloseMessage(WebSocketCloseStatusCode.NORMAL, null);
            } catch (WebSocketException e) {
                warn("Failed to send a CLOSE message when closing connection " ~ this.id.toString(), e);
            }
            this.socket.shutdown(SocketShutdown.BOTH);
            this.socket.close();
            this.messageHandler.onConnectionClosed(this);
        }
    }
}

/**
 * An abstract class that you should extend to define logic for handling
 * websocket messages and events. Create a new class that inherits from this
 * one, and overrides any "on..." methods that you'd like.
 */
abstract class WebSocketMessageHandler {
    /**
     * Called when a new websocket connection is established.
     * Params:
     *   conn = The new connection.
     */
    void onConnectionEstablished(WebSocketConnection conn) {}

    /**
     * Called when a text message is received.
     * Params:
     *   msg = The message that was received.
     */
    void onTextMessage(WebSocketTextMessage msg) {}

    /**
     * Called when a binary message is received.
     * Params:
     *   msg = The message that was received.
     */
    void onBinaryMessage(WebSocketBinaryMessage msg) {}

    /**
     * Called when a CLOSE message is received. Note that this is called before
     * the socket is necessarily guaranteed to be closed.
     * Params:
     *   msg = The close message.
     */
    void onCloseMessage(WebSocketCloseMessage msg) {}

    /**
     * Called when a websocket connection is closed.
     * Params:
     *   conn = The connection that was closed.
     */
    void onConnectionClosed(WebSocketConnection conn) {}
}
