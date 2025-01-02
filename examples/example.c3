// An example of 2 futures executing concurrently using a SimpleRunner.
import std::io;
import c3fut::fut;
import c3fut::simple;

SimpleRunner runner;

fn int main() {
    usz i = 0;
    runner.schedule(fut::poll(fn Result!(any state) {
        usz *i = anycast(state, usz)!!;
        if (*i < 10) {
            io::printfn("%d", *i);
            *i += 1;
            return fut::pending();
        } else {
            return fut::finished(i);
        }
    }, &i).then(fn Future(any result) {
        io::printfn("DONE! %d", *anycast(result, usz)!!);
        return fut::done();
    }));
    runner.schedule(
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
            .then(fn Future(any result) {
                io::printfn("You should never see this");
                return fut::done();
            })
            .@catch(fn Future(any arg, anyfault excuse) {
                io::printfn("One of the futures failed with %s. Recovering...", excuse);
                return fut::done();
            }));
    runner.run()!!;
    return 0;
}
