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
    FutureThenFn f;
}

fn Result! FutureThen.poll(&self) @dynamic {
    if (self.left != null) {
        Result result = self.left.poll()!;
        if (result.finished) {
            self.right = self.f(result.value);
            self.left = null;
        }
        return pending();
    } else {
        assert(self.right != null);
        return self.right.poll();
    }
}

macro Future Future.then(Future left, FutureThenFn f) {
    return @clone(FutureThen {
        .left = left,
        .f = f
    });
}

def FutureCatchFn = fn Future(anyfault excuse);

struct FutureCatch(Future) {
    Future left;
    Future right;
    FutureCatchFn f;
}

fn Result! FutureCatch.poll(&self) @dynamic {
    if (self.left != null) {
        Result! result = self.left.poll();
        if (catch excuse = result) {
            self.right = self.f(excuse);
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
macro Future Future.@catch(Future left, FutureCatchFn f) {
    return @clone(FutureCatch {
        .left = left,
        .f = f
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

def FutureForeverFn = fn Future(any arg);
struct FutureForever(Future) {
    any arg;
    FutureForeverFn forever_fn;
    Future future;
    DynamicArenaAllocator arena;
}

fn Result! FutureForever.poll(&self) @dynamic {
    mem::@scoped(&self.arena) {
        if (self.future == null) {
            self.arena.reset();
            self.future = self.forever_fn(self.arg);
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

macro Future forever(FutureForeverFn forever_fn, any arg = null, Allocator backing_allocator = allocator::heap()) {
    FutureForever future = {
        .arg = arg,
        .forever_fn = forever_fn,
    };
    future.arena.init(20*1024, backing_allocator);
    return @clone(future);
}
