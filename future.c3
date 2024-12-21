module future;

def ThenFunction = fn Future(any result);

interface Future {
    fn any! poll(any data);
}

struct Done(Future) {
    any result;
}

fn any! Done.poll(&self, any data) @dynamic
{
    return self.result;
}

macro Future done(value)
{
    return mem::@tclone(Done{mem::@tclone(value)});
}

struct Reject(Future) {
    anyfault excuse;
}

fn any! Reject.poll(&self, any data) @dynamic
{
    return self.excuse?;
}

fn Future reject(anyfault excuse)
{
    Reject r = {};
    r.excuse = excuse;
    return mem::@tclone(r);
}

struct Then(Future) {
    Future left;
    Future right;
    ThenFunction f;
}

fn any! Then.poll(&self, any data) @dynamic
{
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
    return mem::@tclone(Then {
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
