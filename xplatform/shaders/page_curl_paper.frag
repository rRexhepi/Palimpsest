// Page-turn shader — iBooks-style corner curl.
//
// Single-page mode. The page bends around a fold axis L perpendicular
// to the drag vector (pointer − origin), passing through the current
// finger. The lifted side is the half containing the touchstart — the
// paper the user's hand is "scraping" up. Lifted paper wraps around a
// cylinder of radius r along L, and a back-hanging tail drapes over
// the static side once the drag has consumed more than a full wrap
// (drag > π·r).
//
// The lifted region is bounded by how far the finger has actually
// moved (dragLen). Without that bound, touching mid-page would
// instantly flip half the page; with it, the curl emerges out from
// the finger gradually, dog-ear style.
//
// Per pixel: dProj = signed distance from L, positive on the lifted side.
//   dProj ≤ 0            : static side (current page, or back-hanging).
//   dProj ∈ (0, dragLen] : lifted side; cylinder if dProj ≤ r, else
//                          rolled away (transparent → next page).
//   dProj > dragLen      : paper not yet scraped, still flat.

#include <flutter/runtime_effect.glsl>

uniform vec2 resolution;
uniform vec2 pointer;
uniform vec2 origin;
uniform vec4 container;
uniform float cornerRadius;   // unused
uniform float direction;      // unused (geometry comes from the drag vec)
uniform vec4 backColor;
uniform float hasBack;
uniform float flipSnapshot;   // 1.0 on Impeller (Android) BL-V snapshots;
                              // 0.0 on Skia desktop.
uniform sampler2D image;
uniform sampler2D backImage;

#define PI 3.14159265359
#define TRANSPARENT vec4(0.0, 0.0, 0.0, 0.0)

vec2 uvIn(vec2 p, vec4 rect) {
    return vec2(
        (p.x - rect.x) / max(rect.z - rect.x, 1.0),
        (p.y - rect.y) / max(rect.w - rect.y, 1.0)
    );
}

vec4 sampleSnapshot(sampler2D s, vec2 uv) {
    return texture(s, vec2(uv.x, mix(uv.y, 1.0 - uv.y, flipSnapshot)));
}

bool insideRect(vec2 p, vec4 rect) {
    return p.x >= rect.x && p.x <= rect.z &&
           p.y >= rect.y && p.y <= rect.w;
}

out vec4 fragColor;

void main() {
    vec2 xy = FlutterFragCoord().xy;
    fragColor = TRANSPARENT;

    if (!insideRect(xy, container)) return;

    vec2 drag = pointer - origin;
    float dragLen = length(drag);
    if (dragLen < 1.0) {
        fragColor = sampleSnapshot(image, uvIn(xy, container));
        return;
    }
    vec2 dirLift = -drag / dragLen;
    vec2 F = pointer;

    float pageWidth = max(container.z - container.x, 1.0);
    float r = pageWidth * 0.06;

    float dProj = dot(xy - F, dirLift);

    if (dProj <= 0.0) {
        float dStatic = -dProj;
        // Back-hanging tail reaches here once drag > π·r, and only out
        // to (drag − π·r) past the fold.
        float bhExtent = max(0.0, dragLen - PI * r);
        if (dStatic <= bhExtent) {
            float s_bh = PI * r + dStatic;
            vec2 xOrigBH = F + dirLift * s_bh;
            if (insideRect(xOrigBH, container)) {
                if (hasBack > 0.5) {
                    fragColor = sampleSnapshot(backImage,
                                               uvIn(xOrigBH, container));
                } else {
                    fragColor = backColor;
                }
                return;
            }
        }
        fragColor = sampleSnapshot(image, uvIn(xy, container));
        // Soft shadow under the bulge.
        if (dStatic < r * 2.5) {
            float t = dStatic / (r * 2.5);
            float density = (1.0 - t) * (1.0 - t);
            fragColor.rgb *= mix(1.0 - 0.35 * density, 1.0,
                                 smoothstep(0.0, 1.0, t));
        }
        return;
    }

    if (dProj > dragLen) {
        fragColor = sampleSnapshot(image, uvIn(xy, container));
        return;
    }

    float u = dProj / r;
    if (u <= 1.0) {
        // Cylinder wrap. Back face wins when both candidates are valid;
        // it's the upper half of the wrap, so higher z.
        float s_front = r * asin(u);
        float s_back  = r * (PI - asin(u));
        vec2 xOrigFront = F + dirLift * s_front;
        vec2 xOrigBack  = F + dirLift * s_back;
        float sq = sqrt(max(0.0, 1.0 - u * u));

        if (s_back <= dragLen && insideRect(xOrigBack, container)) {
            if (hasBack > 0.5) {
                fragColor = sampleSnapshot(backImage,
                                           uvIn(xOrigBack, container));
            } else {
                fragColor = backColor;
            }
            fragColor.rgb *= mix(0.7, 1.0, sq);
            return;
        }
        if (s_front <= dragLen && insideRect(xOrigFront, container)) {
            fragColor = sampleSnapshot(image, uvIn(xOrigFront, container));
            fragColor.rgb *= mix(0.88, 1.0, sq);
            return;
        }
        // Both candidates off the page; drop back to flat so the
        // straight-line edge of the page isn't replaced by reveal.
        fragColor = sampleSnapshot(image, uvIn(xy, container));
        return;
    }

    // Past the cylinder, within dragLen: rolled away, reveal layer shows.
}
