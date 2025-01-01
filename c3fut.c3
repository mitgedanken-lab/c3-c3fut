module c3fut::fut;

enum State {
    FINISHED,
    PENDING,
    SLEEPING,
}

struct Result {
    State state;
    any value;
}

macro Result pending() {
    return Result {
        .state = PENDING,
    };
}

macro Result finished(any value = null) {
    return Result {
        .state = FINISHED,
        .value = value,
    };
}

macro Result sleeping(any value = null) {
    return Result {
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
    return @clone(FutureDone{.result = result});
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
    FutureReject r = {};
    r.excuse = excuse;
    return @clone(r);
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
    return @clone(FutureThen {
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
    return @clone(FutureCatch {
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
    return @clone(FuturePoll {
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
    Result! result = self.future.poll();
    if (catch error = result) {
        self.future.destroy();
        self.future = null;
        return error?;
    }
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
    return @clone(FutureForever {
        .state = state,
        .forever_fn = forever_fn,
    });
}
