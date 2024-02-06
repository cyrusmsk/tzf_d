module app;

import tzf_d : DefaultFinder;
import std.getopt;
import std.conv;
import std.stdio;

double lng, lat;
void main(string[] args) {
    auto helpInfo = getopt(
        args,
        "lng", &lng,
        "lat", &lat
    );
    if (helpInfo.helpWanted) {
        defaultGetoptPrinter("Simple CLI for timezone",
        helpInfo.options);
    }
    auto finder = new DefaultFinder();
    auto tz_name = finder.getTzName(lng, lat);
    writeln("Time zone: ", tz_name);
}
