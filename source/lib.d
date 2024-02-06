module tzf_d.lib;

import tzf_d.geomedry : Point, Polygon;
import tzf_d.tzf_rel : load_preindex, load_reduced; 
import gen = pb.tzinfo;
import std.array;
import core.stdc.math : powf, asinh, tan;
import std.math.constants : PI;
import google.protobuf;
import std.conv;
import std.algorithm;
import std.typecons;

struct Item {
    Polygon[] polys;
    string name;

    bool containsPoint(Point p) {
        foreach(poly; this.polys)
            if (poly.containsPoint(p))
                return true;
        return false;
    }
}

class Finder {
    Item[] all;
    string data_version;

    this() {
        // download file
        ubyte[] file_bytes = load_reduced();
        Finder f = new Finder(file_bytes.fromProtobuf!(gen.Timezones));
        this.all = f.all;
        this.data_version = f.data_version;
    }

    this(gen.Timezones tzs) {
        Item[] items;
        auto items_app = appender(&items);
        this.data_version = tzs.version_;

        foreach(tz; tzs.timezones) {
            Polygon[] polys;
            foreach(pbpoly; tz.polygons) {
                Point[] exterior;
                auto exterior_app = appender(&exterior);
                foreach(pbpoint; pbpoly.points) {
                    exterior_app.put(Point(pbpoint.lng, pbpoint.lat));
                }
                Point[][] interior;
                foreach(holepoly; pbpoly.holes) {
                    Point[] holeextr;
                    auto holeextr_app = appender(&holeextr);
                    foreach(holepoint; holepoly.points) {
                        holeextr_app.put(Point(holepoint.lng, holepoint.lat));
                    }
                    interior ~= holeextr;
                }

                // gen::Polygon
                Polygon geopoly = Polygon(exterior, interior);
                polys ~= geopoly;
            }
            items_app.put(Item(polys, tz.name));
        }
        this.all = items;
    }

    string getTzName(double lng, double lat) {
        //geoPoint
        Point p = Point(lng, lat);
        foreach(item; this.all) {
            if (item.containsPoint(p))
                return item.name;
        }
        return "";
    }

    string[] getTzNames(double lng, double lat) {
        string[] ret;
        // geoPoint
        Point p = Point(lng, lat);
        foreach(item; this.all) {
            if (item.containsPoint(p))
                ret ~= item.name;
        }
        return ret;
    }

    string[] timezonenames() {
        string[] ret;
        foreach(item; this.all) {
            ret ~= item.name;
        }
        return ret;
    }

    string dataVersion() {
        return this.data_version;
    }
}

struct PointZoom {
    long lng;
    long lat;
    long zoom;

    static size_t murmur(size_t x) {
        x ^= x >> 13;
        x *= 0x5bd1e995;
        return x ^ (x >> 15);
    }

    size_t toHash() const
    {
        size_t hash;
        auto tmp = [this.lng, this.lat, this.zoom];
        foreach (i; 0..3)
            hash = murmur(hash + tmp[i]);
        return hash;
    }

    bool opEquals(ref const PointZoom s) const
    {
        return tuple(this.lng, this.lat, this.zoom) == tuple(s.lng, s.lat, s.zoom);
    }
}

Tuple!(long, long) deg2num(double lng, double lat, long zoom) {
    double lat_rad = lat * (PI / 180.0);
    double n = powf(2.0, zoom);
    auto xtile = (lng + 180.0) / 360.0 * n;
    auto ytile = (1.0 - lat_rad.tan.asinh / PI) / 2.0 * n;

    // possible precision loss here
    return tuple(cast(long) xtile, cast(long) ytile);
}

class FuzzyFinder {
    long min_zoom;
    long max_zoom;
    string[][PointZoom] all;
    string data_version;

    this() {
        ubyte[] file_bytes = load_preindex();
        FuzzyFinder f = new FuzzyFinder(file_bytes.fromProtobuf!(gen.PreindexTimezones));
        this.min_zoom = f.min_zoom;
        this.max_zoom = f.max_zoom;
        this.all = f.all;
        this.data_version = f.data_version;
    }

    this(gen.PreindexTimezones tzs) {
        string[][PointZoom] for_all;
        this.min_zoom = tzs.aggZoom;
        this.max_zoom = tzs.idxZoom;
        this.data_version = tzs.version_;

        foreach(item; tzs.keys) {
            auto key = PointZoom(item.x, item.y, item.z);
            for_all[key] ~= item.name;
        }
        foreach(item; tzs.keys) {
           auto key = PointZoom(item.x, item.y, item.z); 
           for_all[key].sort();
        }
        this.all = for_all;
    }

    string getTzName (double lng, double lat) {
        string[] ret;
        foreach(zoom; this.min_zoom .. this.max_zoom) {
            auto idx = deg2num(lng, lat, zoom);
            PointZoom k = PointZoom(idx[0], idx[1], zoom);
            string[]* p;
            p = k in this.all;
            if (p is null)
                continue;
            ret = *p;
            break;
        }
        return ret[0];
    }

    string[] getTzNames (double lng, double lat) {
        string[] names;
        foreach(zoom; this.min_zoom .. this.max_zoom) {
            auto idx = deg2num(lng, lat, zoom);
            PointZoom k = PointZoom(idx[0], idx[1], zoom);
            auto p = k in this.all;
            if (p is null)
                continue;
            names ~= *p;
        }
        return names;
    }

    string dataVersion() {
        return this.data_version;
    }
}

class DefaultFinder {
    Finder finder;
    FuzzyFinder fuzzy_finder;

    this() {
        auto fin = new Finder();
        auto fuzzy = new FuzzyFinder();

        this.finder = fin;
        this.fuzzy_finder = fuzzy;
    }

    string getTzName(double lng, double lat) {
        auto fuzzy_name = this.fuzzy_finder.getTzName(lng, lat);
        if (!fuzzy_name.length != 0)
            return fuzzy_name;
        return this.finder.getTzName(lng, lat);
    }

    string[] getTzNames(double lng, double lat) {
        auto fuzzy_names = this.fuzzy_finder.getTzNames(lng, lat);
        if (!fuzzy_names.length != 0)
            return fuzzy_names;
        return this.finder.getTzNames(lng, lat);
    }

    string[] timezonenames() {
        return this.finder.timezonenames;
    }

    string data_version() {
        return this.finder.data_version;
    }
}