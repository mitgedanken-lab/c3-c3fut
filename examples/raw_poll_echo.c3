// Just an example on how to use POSIX's poll(2) raw without any of the future cruft.
import std::io;
import std::net::tcp;
import std::net;
import std::collections::list;
import std::collections::map;

struct Client {
    TcpSocket socket;
    // buffer: aaaaa*****
    //         ^i   ^n
    char[1024] buffer;
    usz i, n;
}

fn bool Client.poll(&self, Poll *poll) {
    switch (poll.events) {
        case net::SUBSCRIBE_READ:
            self.n = self.socket.read(&self.buffer)!!;
            io::printfn("READ %d", self.n);
            if (self.n == 0) return false;
            poll.events = net::SUBSCRIBE_WRITE;
            self.i = 0;
            return true;
        case net::SUBSCRIBE_WRITE:
            usz n = self.socket.write(self.buffer[self.i:self.n])!!;
            io::printfn("WROTE %d", n);
            if (n == 0) return false;
            self.i += n;
            self.n -= n;
            if (self.n == 0) poll.events = net::SUBSCRIBE_READ;
            return true;
        default: unreachable("Unsupported state of the client");
    }
}

fn void main() {
    String host = "localhost";
    uint port = 6969;

    TcpServerSocket server = tcp::listen(host, port, 69, REUSEADDR)!!;
    io::printfn("Listening %s:%d...", host, port);
    server.sock.set_non_blocking(true)!!;

    List(<Poll>) polls;
    polls.push(Poll {
        .socket = server.sock,
        .events = net::SUBSCRIBE_READ,
        .revents = 0,
    });

    HashMap(<NativeSocket, Client>) clients;

    while (true) {
        CInt result = os::poll((Posix_pollfd*)polls.entries, (Posix_nfds_t)polls.len(), (CInt)-1);
        if (result < 0) os::socket_error()?!!;

        for (usz i = 0; i < polls.len();) {
            if (polls[i].revents) {
                if (polls[i].socket == server.sock) {
                    TcpSocket client = tcp::accept(&server)!!;
                    client.sock.set_non_blocking(true)!!;

                    polls.push(Poll {
                        .socket = client.sock,
                        .events = net::SUBSCRIBE_READ,
                        .revents = 0,
                    });
                    clients.set(client.sock, Client{
                        .socket = client,
                    });
                    io::printfn("CONNECTED %d", clients.len());
                } else if (!clients.get_ref(polls[i].socket)!!.poll(&polls[i])) {
                    clients.remove(polls[i].socket);
                    polls[i].socket.close()!!;
                    polls.remove_at(i);
                    io::printfn("DISCONNECTED %d", clients.len());
                    continue; // do not advance the i
                }
            }
            i++;
        }
    }
}
