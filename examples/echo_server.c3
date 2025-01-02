// An example of Asynchronous Echo Server using c3fut
import std::io;
import std::net::tcp;
import std::net::os;
import c3fut::fut;
import c3fut::poll;

PollRunner runner;

fault ClientError {
    CLOSED,
}

struct Client {
    TcpSocket client_sock;
    char[1024] buffer;
    usz i, n;
}

fn Future Client.async_read_once(&client) {
    return fut::poll(fn Result!(any state) {
        Client *client = anycast(state, Client)!!;
        usz! n = client.client_sock.read(&client.buffer);
        if (catch error = n) {
            case IoError.WOULD_BLOCK: return fut::sleeping(@tclone(NativeSocketPoll {
                .socket = client.client_sock.sock,
                .events = net::SUBSCRIBE_READ,
            }));
            default: return error?;
        }
        if (n == 0) return ClientError.CLOSED?;
        client.n = n;
        return fut::finished(client);
    }, client);
}

fn Future Client.async_write_everything(&client) {
    return fut::poll(fn Result!(any state) {
        Client *client = anycast(state, Client)!!;
        if (client.n == 0) return fut::finished(client);
        usz! n = client.client_sock.write(client.buffer[client.i:client.n]);
        if (catch error = n) {
            case IoError.WOULD_BLOCK: return fut::sleeping(@tclone(NativeSocketPoll {
                .socket = client.client_sock.sock,
                .events = net::SUBSCRIBE_WRITE,
            }));
            default: return error?;
        }
        if (n == 0) return ClientError.CLOSED?;
        client.i += n;
        client.n -= n;
        io::printfn("WRITE: %d %d", n, client.n);
        if (client.n == 0) return fut::finished(client);
        return fut::pending();
    }, client);
}

struct Server {
    TcpServerSocket server_sock;
}

fn Future Server.start(&server) {
    return fut::poll(fn Result!(any state) {
        Server *server = anycast(state, Server)!!;
        TcpSocket! client_sock = tcp::accept(&server.server_sock);
        if (catch nani = client_sock) {
            switch (os::socket_error()) {
                case IoError.WOULD_BLOCK: return fut::sleeping(@tclone(NativeSocketPoll {
                    .socket = server.server_sock.sock,
                    .events = net::SUBSCRIBE_READ,
                }));
                default: nani?!!;
            }
        } else {
            client_sock.sock.set_non_blocking(true)!!;
            Client *client = @clone(Client {
                .client_sock = client_sock,
            });
            runner.schedule(fut::forever(fn Future(any arg) {
                Client *client = anycast(arg, Client)!!;
                client.i = 0;
                client.n = 0;
                return client.async_read_once().then(fn Future(any result) {
                    return anycast(result, Client)!!.async_write_everything();
                });
            }, client).@catch(fn Future(any arg, anyfault error) {
                Client *client = anycast(arg, Client)!!;
                if (error == ClientError.CLOSED) {
                    io::printfn("Client disconnected");
                    // TODO: close the socket properly with shutdown and shit
                    client.client_sock.close()!!;
                    free(client);
                    return fut::done();
                }
                return fut::reject(error);
            }, client));
            io::printfn("Client connected");
        }
        return fut::pending();
    }, server);
}

macro @shift(&xs) {
    var x = (*xs)[0];
    (*xs) = (*xs)[1..];
    return x;
}

fn void usage(String program_name) {
    io::eprintfn("Usage: %s [host] [port]", program_name);
}

fn int main(String[] args) {
    String program_name = @shift(args);

    String host = "localhost";
    if (args.len > 0) host = @shift(args);

    uint port = 6969;
    if (args.len > 0) {
        String arg = @shift(args);
        if (try n = arg.to_integer($typeof(port))) {
            port = n;
        } else {
            usage(program_name);
            io::eprintfn("ERROR: `%s` is not a valid integer", arg);
            return 1;
        }
    }

    TcpServerSocket server_sock = tcp::listen(host, port, 69, REUSEADDR)!!;
    io::printfn("Listening to %s:%d...", host, port);
    server_sock.sock.set_non_blocking(true)!!;
    Server server = {.server_sock = server_sock,};

    runner.schedule(server.start());
    runner.run();
    return 0;
}
