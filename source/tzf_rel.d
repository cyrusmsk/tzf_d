module tzf_d.tzf_rel;

import std.file;

ubyte[] load_reduced() {
    return cast(ubyte[])read("tzf-rel/combined-with-oceans.reduce.bin");
}

ubyte[] load_compressed() {
    return cast(ubyte[])read("tzf-rel/combined-with-oceans.reduce.compress.bin");
}

ubyte[] load_preindex() {
    return cast(ubyte[])read("tzf-rel/combined-with-oceans.reduce.preindex.bin");
}
