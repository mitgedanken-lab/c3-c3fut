module future;

// TODO: prefix all the Future structs with "Future", since the types are not namespaces.

interface Future {
    fn any! poll(any data);
}

struct Done(Future) {
    any result;
}

fn any! Done.poll(&self, any data) @dynamic {
    return self.result;
}

macro Future done(value) {
    return @tclone(Done{@tclone(value)});
}

struct Reject(Future) {
    anyfault excuse;
}

fn any! Reject.poll(&self, any data) @dynamic {
    return self.excuse?;
}

fn Future reject(anyfault excuse) {
    Reject r = {};
    r.excuse = excuse;
    return @tclone(r);
}

def ThenFunction = fn Future(any result);

struct Then(Future) {
    Future left;
    Future right;
    ThenFunction f;
}

fn any! Then.poll(&self, any data) @dynamic {
    if (self.left != null) {
        any result = self.left.poll(data)!;
        if (result) {
            self.right = self.f(result);
            self.left = null;
        }
        return null;
    } else {
        assert(self.right != null);
        return self.right.poll(data);
    }
}

macro Future Future.then(Future left, ThenFunction f) {
    return @tclone(Then {
        .left = left,
        .f = f
    });
}

def CatchFunction = fn Future(anyfault excuse);

struct Catch(Future) {
    Future left;
    Future right;
    CatchFunction f;
}

fn any! Catch.poll(&self, any data) @dynamic {
    if (self.left != null) {
        any! result = self.left.poll(data);
        if (catch excuse = result) {
            self.right = self.f(excuse);
            self.left = null;
            return null;
        }
        return result;
    } else {
        assert(self.right != null);
        return self.right.poll(data);
    }
}

// NOTE: We don't really need to call it @catch (I don't remember what @ does, I think it's an
// inline macro or something?), but since catch is a C3 keyword we decided to call
// @catch. If it causes any problems in the future we should consider a different naming.
macro Future Future.@catch(Future left, CatchFunction f) {
    return @tclone(Catch {
        .left = left,
        .f = f
    });
}

fn void! start(Future[] futures) {
    bool quit = false;
    while (!quit) {
        quit = true;
        foreach (future: &futures) {
            if (future.poll(null)! == null) {
                quit = false;
            }
        }
    }
}
