// A same-named METHOD in another directory (a Method is never function-local, so it never yields).
struct Widget
{
    int helper( int v ) { return v - 1; }
};
