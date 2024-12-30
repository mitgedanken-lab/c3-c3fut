module c3fut::fut;

struct Result {
    bool finished;
    any value;
}

macro Result pending() {
    return Result {};
}

macro Result finished(any value = null) {
    return Result {
        .finished = true,
        .value = value
    };
}

interface Future {
    fn Result! poll();
}

struct FutureDone(Future) {
    any result;
}

fn Result! FutureDone.poll(&self) @dynamic {
    return finished(self.result);
}

macro Future done(any result = null) {
    return @clone(FutureDone{.result = result});
}

struct FutureReject(Future) {
    anyfault excuse;
}

fn Result! FutureReject.poll(&self) @dynamic {
    return self.excuse?;
}

fn Future reject(anyfault excuse) {
    FutureReject r = {};
    r.excuse = excuse;
    return @clone(r);
}

def FutureThenFn = fn Future(any result); // TODO: maybe we should allow FutureThenFn fail?

struct FutureThen(Future) {
    Future left;
    Future right;
    FutureThenFn then_fn;
}

fn Result! FutureThen.poll(&self) @dynamic {
    if (self.left != null) {
        Result result = self.left.poll()!;
        if (result.finished) {
            self.right = self.then_fn(result.value);
            self.left = null;
        }
        return pending();
    } else {
        assert(self.right != null);
        return self.right.poll();
    }
}

macro Future Future.then(Future left, FutureThenFn then_fn) {
    return @clone(FutureThen {
        .left = left,
        .then_fn = then_fn,
    });
}

def FutureCatchFn = fn Future(anyfault excuse);

struct FutureCatch(Future) {
    Future left;
    Future right;
    FutureCatchFn catch_fn;
}

fn Result! FutureCatch.poll(&self) @dynamic {
    if (self.left != null) {
        Result! result = self.left.poll();
        if (catch excuse = result) {
            self.right = self.catch_fn(excuse);
            self.left = null;
            return pending();
        }
        return result;
    } else {
        assert(self.right != null);
        return self.right.poll();
    }
}

// NOTE: We don't really need to call it @catch (I don't remember what @ does, I think it's an
// inline macro or something?), but since catch is a C3 keyword we decided to call
// @catch. If it causes any problems in the future we should consider a different naming.
macro Future Future.@catch(Future left, FutureCatchFn catch_fn) {
    return @clone(FutureCatch {
        .left = left,
        .catch_fn = catch_fn
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

macro Future poll(FuturePollFn poll_fn, any state = null) {
    return @clone(FuturePoll {
        .state = state,
        .poll_fn = poll_fn,
    });
}

def FutureForeverFn = fn Future(any state);
struct FutureForever(Future) {
    any state;
    FutureForeverFn forever_fn;
    Future future;
    DynamicArenaAllocator arena;
}

fn Result! FutureForever.poll(&self) @dynamic {
    mem::@scoped(&self.arena) {
        if (self.future == null) {
            self.arena.reset();
            self.future = self.forever_fn(self.state);
        }
        Result! result = self.future.poll();
        if (catch error = result) {
            self.arena.free();
            self.future = null;
            return error?;
        } else if (result.finished) {
            self.future = null;
        }
        return pending();
    };
}

macro Future forever(FutureForeverFn forever_fn, any state = null, Allocator backing_allocator = allocator::heap()) {
    FutureForever future = {
        .state = state,
        .forever_fn = forever_fn,
    };
    future.arena.init(20*1024, backing_allocator);
    return @clone(future);
}
