module c3fut::fut;

fault FutureError {
    SLEEPING_UNSUPPORTED,
}

enum State {
    // The future is finished, and Result.value contains the result of its
    // execusion.  Consequent calls of Future.poll() after receiving this
    // Result.state are not advised.
    FINISHED,
    // The future did a bit of work but it's not finished yet. The runner may
    // continue calling Future.poll() until the Result is FINISHED.
    // Result.value should be ignored.
    PENDING,
    // The future requests the runner to put it to sleep during which
    // Future.poll() should not called until an event described in Result.value
    // occurs. The exact type of Result.value is up to the runner and the
    // future to agree upon. It is also recommended for the futures that request
    // sleeping to allocate Result.value in allocator::value().
    //
    // This state is usually used in Async IO when certain non-blocking file
    // descriptors fail with IoError.WOULD_BLOCK, so
    // the runner may employ such mechanisms as select/poll/epoll to postpone
    // execution of the sleeping futures until the file descriptors are
    // readable/writable again
    SLEEPING,
}

struct Result {
    State state;
    any value;
}

macro Result pending() {
    return {
        .state = PENDING,
    };
}

macro Result finished(any value = null) {
    return {
        .state = FINISHED,
        .value = value,
    };
}

macro Result sleeping(any value = null) {
    return {
        .state = SLEEPING,
        .value = value
    };
}

interface Future {
    fn Result! poll();
    fn void destroy();
}

struct FutureDone(Future) {
    any result;
}

fn Result! FutureDone.poll(&self) @dynamic {
    return finished(self.result);
}

fn void FutureDone.destroy(&self) @dynamic {
    free(self);
}

macro Future done(any result = null) {
    return mem::new(FutureDone, {.result = result});
}

struct FutureReject(Future) {
    anyfault excuse;
}

fn Result! FutureReject.poll(&self) @dynamic {
    return self.excuse?;
}

fn void FutureReject.destroy(&self) @dynamic {
    free(self);
}

fn Future reject(anyfault excuse) {
    return mem::new(FutureReject, { .excuse = excuse });
}

def FutureThenFn = fn Future(any result);

struct FutureThen(Future) {
    Future left;
    Future right;
    FutureThenFn then_fn;
}

fn Result! FutureThen.poll(&self) @dynamic {
    if (self.left != null) {
        Result result = self.left.poll()!;
        if (result.state == FINISHED) {
            self.right = self.then_fn(result.value);
            self.left.destroy();
            self.left = null;
            return pending();
        }
        return result;
    } else {
        assert(self.right != null);
        return self.right.poll();
    }
}

fn void FutureThen.destroy(&self) @dynamic {
    if (self.left)  self.left.destroy();
    if (self.right) self.right.destroy();
    free(self);
}

macro Future Future.then(Future left, FutureThenFn then_fn) {
    return mem::new(FutureThen, {
        .left = left,
        .then_fn = then_fn,
    });
}

def FutureCatchFn = fn Future(any arg, anyfault excuse);

struct FutureCatch(Future) {
    any arg;
    Future left;
    Future right;
    FutureCatchFn catch_fn;
}

fn Result! FutureCatch.poll(&self) @dynamic {
    if (self.left != null) {
        Result! result = self.left.poll();
        if (catch excuse = result) {
            self.right = self.catch_fn(self.arg, excuse);
            self.left = null;
            return pending();
        }
        return result;
    } else {
        assert(self.right != null);
        return self.right.poll();
    }
}

fn void FutureCatch.destroy(&self) @dynamic {
    if (self.left) self.left.destroy();
    if (self.right) self.right.destroy();
    free(self);
}

// NOTE: We don't really need to call it @catch (I don't remember what @ does, I think it's an
// inline macro or something?), but since catch is a C3 keyword we decided to call
// @catch. If it causes any problems in the future we should consider a different naming.
macro Future Future.@catch(Future left, FutureCatchFn catch_fn, any arg = null) {
    return mem::new(FutureCatch, {
        .left = left,
        .catch_fn = catch_fn,
        .arg = arg,
    });
}

def FuturePollFn = fn Result!(any state);

struct FuturePoll(Future) {
    any state;
    FuturePollFn poll_fn;
}

fn Result! FuturePoll.poll(&self) @dynamic {
    return self.poll_fn(self.state);
}

fn void FuturePoll.destroy(&self) @dynamic {
    free(self);
}

macro Future poll(FuturePollFn poll_fn, any state = null) {
    return mem::new(FuturePoll, {
        .state = state,
        .poll_fn = poll_fn,
    });
}

// TODO: Maybe symantically FutureForeverFn should FutureThenFn
// So you can think of fut::forever as a infinite .then() that
// constantly feeds into itself
def FutureForeverFn = fn Future(any state);
struct FutureForever(Future) {
    any state;
    FutureForeverFn forever_fn;
    Future future;
}

fn Result! FutureForever.poll(&self) @dynamic {
    if (self.future == null) self.future = self.forever_fn(self.state);

    defer catch {
        self.future.destroy();
        self.future = null;
    }

    // Will run the defer on error
    Result result = self.future.poll()!;

    if (result.state == FINISHED) {
        self.future.destroy();
        self.future = null;
        return pending();
    }
    return result;
}

fn void FutureForever.destroy(&self) @dynamic {
    if (self.future) self.future.destroy();
    free(self);
}

macro Future forever(FutureForeverFn forever_fn, any state = null) {
    return mem::new(FutureForever, {
        .state = state,
        .forever_fn = forever_fn,
    });
}

module c3fut::simple;

import c3fut::fut;
import std::collections::list;

struct SimpleRunner {
    List(<Future>) futures;
}

fn void SimpleRunner.schedule(&self, Future future) {
    self.futures.push(future);
}

fn bool SimpleRunner.done(&self) {
    return self.futures.len() == 0;
}

fn void! SimpleRunner.run(&self) {
    while (!self.done()) {
        for (usz i = 0; i < self.futures.len();) {
            Result result = self.futures[i].poll()!;
            switch (result.state) {
                case PENDING: ++i;
                case SLEEPING: return FutureError.SLEEPING_UNSUPPORTED?;
                case FINISHED:
                    self.futures.swap(i, self.futures.len()-1);
                    self.futures.pop()!!.destroy();
            }
        }
    }
}

module c3fut::poll;

import c3fut::fut;
import std::collections::list;
import std::collections::map;
import std::net;

struct NativeSocketPoll {
    NativeSocket socket;
    PollSubscribes events;
}

struct PollRunner {
    List(<Future>) kitchen; // cooking futures
    List(<Future>) dirty_kitchen;
    HashMap(<NativeSocket, Future>) bed; // sleeping future ( -.-).zZ
    List(<Poll>) polls;
}

fn void PollRunner.schedule(&self, Future future) {
    self.dirty_kitchen.push(future);
}

fn bool PollRunner.done(&self) {
    return self.kitchen.len() == 0 && self.bed.len() == 0;
}

fn void PollRunner.run(&runner) {
    runner.kitchen.clear();
    @swap(runner.kitchen, runner.dirty_kitchen);
    while (!runner.done()) {
        @pool() {
            foreach (future: runner.kitchen) {
                Result result = future.poll()!!;
                switch (result.state) {
                    case PENDING:
                        runner.dirty_kitchen.push(future);
                    case SLEEPING:
                        NativeSocketPoll *wait = anycast(result.value, NativeSocketPoll)!!;
                        runner.bed.set(wait.socket, future);
                        runner.polls.push({
                            .socket = wait.socket,
                            .events = wait.events,
                        });
                    case FINISHED:
                        future.destroy();
                }
            }

            runner.kitchen.clear();
            @swap(runner.kitchen, runner.dirty_kitchen);

            // TODO: use net::poll() instead of os::poll() here
            CInt timeout = runner.kitchen.len() == 0 ? (CInt)-1 : (CInt) 0;
            CInt result = os::poll((Posix_pollfd*)runner.polls.entries, (Posix_nfds_t)runner.polls.len(), timeout);
            if (result < 0) os::socket_error()?!!;

            for (usz i = 0; i < runner.polls.len();) {
                if (runner.polls[i].revents) {
                    Future future = runner.bed.get(runner.polls[i].socket)!!;
                    runner.kitchen.push(future);
                    runner.polls.remove_at(i);
                } else {
                    ++i;
                }
            }
        };
    }
}
