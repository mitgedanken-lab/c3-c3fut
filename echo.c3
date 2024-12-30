import std::io;
import std::thread;
import std::net::tcp;
import std::net::os;
import std::collections::list;
import c3fut::fut;

const bool ASYNC = true;

fault ClientError {
    CLOSED,
}

struct Client {
    TcpSocket client_sock;
    Future future;
    char[1024] buffer;
    usz i, n;
}

struct Server {
    TcpServerSocket server_sock;
    Future future;
    List(<Client*>) *clients;
}

fn Future client_async_read_once(Client *client) {
    return fut::poll(fn Result!(any state, any env) {
        Client *client = anycast(state, Client)!!;
        usz! n = client.client_sock.read(&client.buffer);
        if (catch error = n) {
            case IoError.WOULD_BLOCK: return fut::pending();
            default: return error?;
        }
        if (n == 0) return ClientError.CLOSED?;
        client.n = n;
        return fut::finished(client);
    }, client);
}

fn Future client_async_write_everything(Client *client) {
    return fut::poll(fn Result!(any state, any env) {
        Client *client = anycast(state, Client)!!;
        if (client.n == 0) return fut::finished(client);
        usz! n = client.client_sock.write(client.buffer[client.i:client.n]);
        if (catch error = n) {
            case IoError.WOULD_BLOCK: return fut::pending();
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

fn Future client_async_catch_error(anyfault error) {
    if (error == ClientError.CLOSED) return fut::done();
    return fut::reject(error);
}

fn void main() {
    TcpServerSocket server_sock = tcp::listen("localhost", 6969, 69, REUSEADDR)!!;

$if ASYNC:
    server_sock.sock.set_non_blocking(true)!!;

    List(<Client*>) clients;
    List(<Client*>) clients_next;

    Server server = {
        .server_sock = server_sock,
        .clients = &clients,
    };
    server.future = fut::poll(fn Result!(any state, any env) {
        Server *server = anycast(state, Server)!!;
        TcpSocket! client_sock = tcp::accept(&server.server_sock);
        if (catch nani = client_sock) {
            switch (os::socket_error()) {
                case IoError.WOULD_BLOCK: return fut::pending();
                default: nani?!!;
            }
        } else {
            client_sock.sock.set_non_blocking(true)!!;
            Client *client = @clone(Client {
                .client_sock = client_sock,
            });
            client.future = fut::forever(fn Future(any arg) {
                Client *client = anycast(arg, Client)!!;
                client.i = 0;
                client.n = 0;
                return client_async_read_once(client).then(fn Future(any result) {
                    return client_async_write_everything(anycast(result, Client)!!);
                });
            }, client).@catch(&client_async_catch_error);
            server.clients.push(client);
            io::printfn("Client connected");
        }
        return fut::pending();
    }, &server);
$endif

    while (true) {
$if ASYNC:
        server.future.poll()!!;
        foreach (client: clients) {
            if (!client.future.poll()!!.finished) {
                clients_next.push(client);
            } else {
                io::printfn("Client disconnected");
                client.client_sock.close()!!;
                free(client.future);
                free(client);
            }
        }
        clients.clear();
        @swap(clients, clients_next);
$else
        TcpSocket! client_sock = tcp::accept(&server_sock);
        Thread client_thread;
        client_thread.create(fn int(void* arg) {
            TcpSocket* client_sock = (TcpSocket*)arg;
            defer {
                client_sock.close()!!;
                free(client_sock);
                io::printfn("Client disconnected");
            }
            char[1024] buffer;
            while (true) {
                usz n = client_sock.read(&buffer)!!;
                if (n == 0) break;
                client_sock.write(buffer[0:n])!!;
            }
            return 0;
        }, @clone(client_sock))!!;
        client_thread.detach()!!;
$endif
    }
}
