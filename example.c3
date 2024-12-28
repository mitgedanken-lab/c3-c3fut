import std::io;
import std::collections::list;
import c3fut::fut;

fn int main() {
    List(<Future>) futures;
    usz i = 0;
    futures.push(fut::poll(fn any!(any state, any data) {
        usz *i = anycast(state, usz)!!;
        if (*i < 10) {
            io::printfn("%d", *i);
            *i += 1;
            return null;
        } else {
            return state;
        }
    }, &i).then(fn Future(any result) {
        io::printfn("DONE!");
        return fut::done(null);
    }));
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
