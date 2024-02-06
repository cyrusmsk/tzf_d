module tzf_d.tzf_rel;

import std.file;

ubyte[] load_reduced() {
    return cast(ubyte[])read("data/combined-with-oceans.reduce.pb");
}

ubyte[] load_compressed() {
    return cast(ubyte[])read("data/combined-with-oceans.reduce.compress.pb");
}

ubyte[] load_preindex() {
    return cast(ubyte[])read("data/combined-with-oceans.reduce.preindex.pb");
}