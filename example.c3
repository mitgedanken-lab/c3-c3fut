import std::io;
import std::collections::list;
import c3fut::fut;

fn int main() {
    List(<Future>) futures;
    usz i = 0;
    futures.push(fut::poll(fn Result!(any state, any env) {
        usz *i = anycast(state, usz)!!;
        if (*i < 10) {
            io::printfn("%d", *i);
            *i += 1;
            return fut::pending();
        } else {
            return fut::finished();
        }
    }, &i).then(fn Future(any result) {
        io::printfn("DONE!");
        return fut::done();
    }));
    futures.push(
        fut::done((int*)69) // NOTE: Lernö does not allow you to store
                            // primitive values in `any` because he is
                            // authoritarian like that. But creative
                            // freedom always finds its way!
            .then(fn Future(any result) {
                io::printfn("%d", result.ptr);
                return fut::done((int*)420);
            })
            .then(fn Future(any result) {
                io::printfn("%d", result.ptr);
                return fut::done((int*)1337);
            })
            .then(fn Future(any result) {
                io::printfn("%d", result.ptr);
                return fut::reject(IoError.WOULD_BLOCK);
            })
            .@catch(fn Future(anyfault excuse) {
                io::printfn("One of the futures failed with %s. Recovering...", excuse);
                return fut::done(null);
            }));
    bool quit = false;
    while (!quit) {
        quit = true;
        foreach (&future: futures) {
            if (!future.poll(null)!!.finished) {
                quit = false;
            }
        }
    }
    return 0;
}
