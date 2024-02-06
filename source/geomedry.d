module tzf_d.geomedry;

import rtree;
import std.experimental.allocator.gc_allocator : GCAllocator;
import std.math.operations : nextafter;
import std.array : appender;
import std.algorithm.mutation : swap;

alias MyTree = RTree!(GCAllocator, long, double, 2, double);

struct Point {
    double x;
    double y;
}

struct Rect {
    Point r_min;
    Point r_max;

    bool containsPoint(Point p) {
        return p.x >= this.r_min.x && p.x <= this.r_max.x &&
               p.y >= this.r_min.y && p.y <= this.r_max.y;
    }

    bool intersectsRect(Rect other) {
        if (this.r_min.y > other.r_max.y || this.r_max.y < other.r_min.y)
            return false;
        if (this.r_min.x > other.r_max.x || this.r_max.x < other.r_min.x)
            return false;
        return true;
    }

    Point nw() {
        return Point(this.r_min.x, this.r_max.y);
    }

    Point sw() {
        return Point(this.r_min.x, this.r_min.y);
    }

    Point se() {
        return Point(this.r_max.x, this.r_min.y);
    }

    Point ne() {
        return Point(this.r_max.x, this.r_max.y);
    }

    Segment south() {
        return Segment(this.sw(), this.se());
    }

    Segment east() {
        return Segment(this.se(), this.ne());
    }

    Segment north() {
        return Segment(this.ne(), this.nw());
    }

    Segment west() {
        return Segment(this.nw(), this.sw());
    }

    Segment segmentAt(long index) {
        switch(index) {
            case 0:
                return this.south();
            case 1:
                return this.east();
            case 2:
                return this.north();
            case 3:
                return this.west();
            default:
                return this.south(); // TODO(ringsaturn): raise err
        }
    }
}

Segment segmentAtForVecPoint(Point[] exterior, long index) {
    Point seg_a = exterior[index];
    long seg_b_index = exterior.length == 1 ? 0 : index + 1;
    Point seg_b = exterior[seg_b_index];
    return Segment(seg_a, seg_b);
}

bool ringsContainsPoint(Point[] ring, Point point, bool allow_on_edge) {
    Rect rect = Rect(
                    Point(-double.infinity, point.y),
                    Point(double.infinity, point.y)
            );
    bool inside = false;
    long n = ring.length;
    foreach(i; 0..n) {
        Segment seg = segmentAtForVecPoint(ring, i);
        
        if (seg.rect().intersectsRect(rect)) {
            Raycast res = Raycast(seg, point);
            if (res.on) {
                inside = allow_on_edge;
                break;
            }
            if (res.inside) {
                inside = !inside;
            }
        }
    }
    return inside;
}

bool ringsContainsPointByRtreeIndex(Point[] ring,
        MyTree ring_rtree,
        Point point,
        bool allow_on_edge) {
    Rect rect = Rect(
                    Point(-double.infinity, point.y),
                    Point(double.infinity, point.y)
            );

    foreach(item; ring_rtree.search([-double.infinity, point.y],
                                    [double.infinity, point.y])) {
        Segment seg = segmentAtForVecPoint(ring, item);
        if (seg.rect().intersectsRect(rect)) {
            Raycast res = Raycast(seg, point);
            if (res.on)
                return allow_on_edge;
            if (res.inside)
                return true;
        }
    }
    return false;
}

struct Polygon {
    Point[] exterior;
    MyTree exterior_rtree;
    Point[][] holes;
    MyTree[] holes_rtree;
    Rect rect;
    bool with_index;

    bool containsPointWithIndex(Point p) {
        if (!ringsContainsPointByRtreeIndex(this.exterior, this.exterior_rtree, p, false))
            return false;
        bool contains = false;
        foreach(i, hole; holes) {
            auto tr = this.holes_rtree[i];
            if (ringsContainsPointByRtreeIndex(hole, tr, p, false)) {
                contains = true;
                break;
            }
        }
        return contains;
    }

    bool containsPointNormal(Point p) {
        if (!ringsContainsPoint(this.exterior, p, false))
            return false;
        bool contains = true;
        foreach(hole; holes)
            if (ringsContainsPoint(hole, p, false)) {
                contains = false;
                break;
            }
        return contains;
    }

    bool containsPoint(Point p) {
        if (!this.rect.containsPoint(p))
            return false;
        if (this.with_index)
            return this.containsPointWithIndex(p);
        return this.containsPointNormal(p);
    }

    this(Point[] exterior, Point[][] holes, bool with_index = false) {
        double minx = exterior[0].x;
        double miny = exterior[0].y;
        double maxx = exterior[0].x;
        double maxy = exterior[0].y;

        auto n = exterior.length;
        foreach(i; 0..n) {
            auto p = exterior[i];
            if (p.x < minx)
                minx = p.x;
            if (p.y < miny)
                miny = p.y;
            if (p.x > maxx)
                maxx = p.x;
            if (p.y > maxy)
                maxy = p.y;
        }

        Rect tmp_rect = Rect(Point(minx, miny), Point(maxx,maxy));
        auto exterior_rtree = RTree!(GCAllocator, long, double, 2, double).make();

        foreach(i; 0..n) {
            auto segrect = segmentAtForVecPoint(exterior, i).rect();
            if (with_index) {
                exterior_rtree.insert(
                        [segrect.r_min.x, segrect.r_min.y],
                        [segrect.r_max.x, segrect.r_max.y],
                        i
                );
            }
        }
        MyTree[] tmp_holes_rtree;
        auto app = appender(&tmp_holes_rtree);

        foreach(hole_poly; holes) {
            auto hole_rtre = RTree!(GCAllocator, long, double, 2, double).make();
            long k = hole_poly.length;
            foreach(i; 0..k) {
                auto segrect = segmentAtForVecPoint(hole_poly, i).rect();
                if (with_index) {
                    hole_rtre.insert(
                            [segrect.r_min.x, segrect.r_min.y],
                            [segrect.r_max.x, segrect.r_max.y],
                            i
                    );
                }
            }
            if (with_index)
                app.put(hole_rtre);
        }

        this.exterior = exterior;
        this.exterior_rtree = exterior_rtree;
        this.holes = holes;
        this.holes_rtree = tmp_holes_rtree;
        this.rect = tmp_rect;
        this.with_index = with_index;
    }
}

struct Segment {
    Point a;
    Point b;

    Rect rect() {
        double min_x = this.a.x;
        double min_y = this.a.y;
        double max_x = this.b.x;
        double max_y = this.b.y;

        if (min_x > max_x)
            swap(min_x, max_x);
        if (min_y > max_y)
            swap(min_y, max_y);

        return Rect(Point(min_x, min_y), Point(max_x,max_y));
    }
}

struct Raycast{
    bool inside;
    bool on;

    this(Segment seg, Point point) {
        Point p = point;
        auto a = seg.a;
        auto b = seg.b;

        if (a.y < b.y && (p.y < a.y || p.y > b.y)) {
            this.inside = false;
            this.on = false;
            return;
        }
        else if (a.y > b.y && (p.y < b.y || p.y > a.y)) {
            this.inside = false;
            this.on = false;
            return;
        }

        if (a.y == b.y) {
            if (a.x == b.x) {
                if (p.x == a.x && p.y == a.y) {
                    this.inside = false;
                    this.on = true;
                    return;
                }
                this.inside = false;
                this.on = false;
                return;
            }
            if (p.y == b.y) {
                // horizontal segment
                // check if the point in on the line
                if (a.x < b.x) {
                    if (p.x >= a.x && p.x <= b.x) {
                        this.inside = false;
                        this.on = true;
                        return;
                    }
                } else {
                    if (p.x >= b.x && p.x <= a.x) {
                        this.inside = false;
                        this.on = true;
                        return;
                    }
                }
            }
        }
        if (a.x == b.x && p.x == b.x) {
            // vertical segment
            // check if the point in on the line
            if (a.y < b.y) {
                if (p.y >= a.y && p.y <= b.y) {
                    this.inside = false;
                    this.on = true;
                    return;
                }
            } else {
                if (p.y >= b.y && p.y <= a.y) {
                    this.inside = false;
                    this.on = true;
                    return;
                }
            }
        }
        if ((p.x - a.x) / (b.x - a.x) == (p.y - a.y) / (b.y - a.y)) {
            this.inside = false;
            this.on = true;
            return;
        }
        
        // do the actual raycast here
        while (p.y == a.y || p.y == b.y)
            p.y = nextafter(p.y, p.y.infinity);

        if (a.y < b.y) {
            if (p.y < a.y || p.y > b.y) {
                this.inside = false;
                this.on = false;
                return;
            }
        } else {
            if (p.y < b.y || p.y > a.y) {
                this.inside = false;
                this.on = false;
                return;
            }
        }

        if (a.x > b.x) {
            if (p.x >= a.x) {
                this.inside = false;
                this.on = false;
                return;
            }
            if (p.x <= b.x) {
                this.inside = true;
                this.on = false;
                return;
            }
        } else {
            if (p.x >= b.x) {
                this.inside = false;
                this.on = false;
                return;
            }
            if (p.x <= a.x) {
                this.inside = true;
                this.on = false;
                return;
            }
        }

        if (a.y < b.y) {
            if ((p.y - a.y) / (p.x - a.x) >= (b.y - a.y) / (b.x - a.x)) {
                this.inside = true;
                this.on = false;
                return;
            }
        } else {
            if ((p.y - b.y) / (p.x - b.x) >= (a.y - b.y) / (a.x - b.x)) {
                this.inside = true;
                this.on = false;
                return;
            }
        }

        this.inside = false;
        this.on = false;
    }
}
