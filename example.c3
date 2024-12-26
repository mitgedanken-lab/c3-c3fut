import std::io;
import std::collections::list;
import c3fut::fut;

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
    futures.push(
        fut::done(69)
            .then(fn Future(any result) {
                io::printfn("%s", result);
                return fut::done(420);
            })
            .then(fn Future(any result) {
                io::printfn("%s", result);
                return fut::done(1337);
            })
            .then(fn Future(any result) {
                io::printfn("%s", result);
                return fut::reject(IoError.WOULD_BLOCK);
            })
            .@catch(fn Future(anyfault excuse) {
                io::printfn("One of the futures failed with %s. Recovering...", excuse);
                return fut::done(null);
            }));
    fut::start(futures.array_view())!!;
    return 0;
}
