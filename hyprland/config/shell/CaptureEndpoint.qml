import Quickshell
import Quickshell.Io

// Small newline-delimited JSON endpoint on the session's private runtime dir.
SocketServer {
    id: server
    property string endpoint: ""
    signal request(var message, var client)
    active: endpoint !== ""
    path: endpoint ? Quickshell.env("XDG_RUNTIME_DIR") + "/" + endpoint : ""
    function reply(client, value) {
        client.write(JSON.stringify(value) + "\n");
        client.flush();
    }
    handler: Socket {
        id: client
        parser: SplitParser {
            onRead: line => {
                try { server.request(JSON.parse(line), client); }
                catch (error) { server.reply(client, {error: String(error)}); }
            }
        }
    }
}
