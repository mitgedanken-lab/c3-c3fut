import std::io;
import std::collections::list;
import future;

struct Counter(Future) {
    int i, n;
}

macro Future counter(int i, int n) {
    return @tclone(Counter {i, n});
}

fn void Counter.reset(&self) {
    self.i = 0;
}

fn any! Counter.poll(&self, any data) @dynamic {
    if (self.i < self.n) {
        io::printfn("%d", self.i);
        self.i += 1;
        return null;
    } else {
        return @tclone(self.n);
    }
}

fn int main() {
    List(<Future>) futures;
    futures.push(counter(1, 10));
    futures.push(future::done(69).then(fn Future(any result) {
        io::printfn("%s", result);
        return future::done(420);
    }).then(fn Future(any result) {
        io::printfn("%s", result);
        return future::done(1337);
    }).then(fn Future(any result) {
        io::printfn("%s", result);
        return future::reject(IoError.WOULD_BLOCK);
    }));
    if (catch err = future::start(futures.array_view())) {
        io::printfn("One of the futures failed with %s", err);
        return 1;
    }
    return 0;
}
