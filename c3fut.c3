module c3fut::fut;

interface Future {
    fn any! poll(any env);
}

struct FutureDone(Future) {
    any result;
}

fn any! FutureDone.poll(&self, any env) @dynamic {
    return self.result;
}

macro Future done(value) {
    return @clone(FutureDone{@clone(value)});
}

struct FutureReject(Future) {
    anyfault excuse;
}

fn any! FutureReject.poll(&self, any env) @dynamic {
    return self.excuse?;
}

fn Future reject(anyfault excuse) {
    FutureReject r = {};
    r.excuse = excuse;
    return @clone(r);
}

def FutureThenFunction = fn Future(any result);

struct FutureThen(Future) {
    Future left;
    Future right;
    FutureThenFunction f;
}

fn any! FutureThen.poll(&self, any env) @dynamic {
    if (self.left != null) {
        any result = self.left.poll(env)!;
        if (result) {
            self.right = self.f(result);
            self.left = null;
        }
        return null;
    } else {
        assert(self.right != null);
        return self.right.poll(env);
    }
}

macro Future Future.then(Future left, FutureThenFunction f) {
    return @clone(FutureThen {
        .left = left,
        .f = f
    });
}

def FutureCatchFunction = fn Future(anyfault excuse);

struct FutureCatch(Future) {
    Future left;
    Future right;
    FutureCatchFunction f;
}

fn any! FutureCatch.poll(&self, any env) @dynamic {
    if (self.left != null) {
        any! result = self.left.poll(env);
        if (catch excuse = result) {
            self.right = self.f(excuse);
            self.left = null;
            return null;
        }
        return result;
    } else {
        assert(self.right != null);
        return self.right.poll(env);
    }
}

// NOTE: We don't really need to call it @catch (I don't remember what @ does, I think it's an
// inline macro or something?), but since catch is a C3 keyword we decided to call
// @catch. If it causes any problems in the future we should consider a different naming.
macro Future Future.@catch(Future left, FutureCatchFunction f) {
    return @clone(FutureCatch {
        .left = left,
        .f = f
    });
}

def FuturePollFn = fn any!(any state, any env);

struct FuturePoll(Future) {
    any state;
    FuturePollFn poll_fn;
}

fn any! FuturePoll.poll(&self, any env) @dynamic {
    return self.poll_fn(self.state, env);
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

fn any! FutureForever.poll(&self, any env) @dynamic {
    mem::@scoped(&self.arena) {
        if (self.future == null) {
            self.arena.reset();
            self.future = self.forever_fn(self.arg);
        }
        if (self.future.poll(env)!) self.future = null;
        return null;
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
