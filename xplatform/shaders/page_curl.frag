// Page-turn shader — rigid rotation around the spine.
//
// We model the flipping leaf as a rigid rectangle hinged at the spine.
// As the user drags, the leaf rotates around the spine by angle θ:
//
//   θ = 0      → page flat on its original side (front visible)
//   θ = π/2    → page vertical at the spine (a line, nothing readable)
//   θ = π      → page flat on the opposite side (back visible)
//
// For a paper point originally at distance d from the spine:
//   * visible viewport position: spine + d·cos(θ)
//   * height above surface:      d·sin(θ)
//
// The book convention: page N+1 is printed on the BACK of leaf N such
// that at θ = π the back reads correctly. That means the back content
// at paper position p (in original [spine, spine+pageWidth] coords)
// holds page N+1 at the spine-mirror position (2·spine − p).
//
// progress mapping: dx / pageWidth ∈ [0, 2] → θ ∈ [0, π].
//   progress 0 → page flat (no curl)
//   progress 1 → page vertical
//   progress 2 → page flat on other side (fully flipped)

#include <flutter/runtime_effect.glsl>

uniform vec2 resolution;
uniform float pointer;
uniform float origin;
uniform vec4 container;       // flipping leaf rect in viewport coords
uniform float cornerRadius;   // (unused for now)
uniform float direction;      // 0.0 = forward, 1.0 = backward
uniform vec4 backColor;       // fallback parchment when no back texture
uniform float hasBack;        // 1.0 → sample backImage on the back face,
                              // 0.0 → fall back to backColor parchment.
uniform sampler2D image;      // current page (= leaf's front)
uniform sampler2D backImage;  // page on the back of the curling leaf

#define PI 3.14159265359
#define HALF_PI 1.5707963267948966
#define TRANSPARENT vec4(0.0, 0.0, 0.0, 0.0)

vec2 sampleUVIn(vec2 p, vec4 rect) {
    return vec2(
        (p.x - rect.x) / max(rect.z - rect.x, 1.0),
        (p.y - rect.y) / max(rect.w - rect.y, 1.0)
    );
}

out vec4 fragColor;

void main() {
    vec2 xy = FlutterFragCoord().xy;
    fragColor = TRANSPARENT;

    bool forward = direction < 0.5;
    float dx = forward ? (origin - pointer) : (pointer - origin);
    float pageWidth = max(container.z - container.x, 1.0);
    float progress = clamp(dx / pageWidth, 0.0, 2.0);

    float theta = progress * HALF_PI;
    float c = cos(theta);
    float s = sin(theta);

    // The spine = the edge of the flipping leaf adjacent to the static
    // page. Forward turns rotate around `container.x`, backward around
    // `container.z`. `sign` points outward from the spine into the
    // flipping leaf's original half.
    float spine = forward ? container.x : container.z;
    float spineSign = forward ? 1.0 : -1.0;

    // The leaf's leading edge (originally at container.z for forward)
    // after rotation by θ. At θ=0 it's at the original right edge; at
    // θ=π/2 it's right at the spine; at θ=π it's at the far left.
    float farEdge = spine + spineSign * pageWidth * c;

    // Sorted page bounds — the strip of viewport the rotated leaf
    // currently occupies on the X axis. We clip everything to the
    // card's vertical extent too, otherwise the back-face fill /
    // shadow zone bleeds into the chrome padding above and below
    // the card (visible as parchment-coloured bars during the flip).
    float pageLo = min(spine, farEdge);
    float pageHi = max(spine, farEdge);
    bool inCardY = xy.y >= container.y && xy.y <= container.w;
    bool xyOnPage = xy.x >= pageLo && xy.x <= pageHi && inCardY;

    bool xyOnStaticSide =
        (forward ? (xy.x < spine) : (xy.x > spine)) && inCardY;
    bool showingBack = theta > HALF_PI;

    if (xyOnPage && abs(c) > 0.002) {
        // Map viewport x back to paper position via the rotation:
        //   xy.x = spine + spineSign * d * c, where d = |pPaper - spine|
        //   so pPaper = spine + (xy.x - spine) / c. (spineSign cancels.)
        float pPaper = spine + (xy.x - spine) / c;
        pPaper = clamp(pPaper, container.x, container.z);

        if (showingBack) {
            // Past vertical — viewer sees the back face. If the host
            // supplied the destination page as `backImage`, sample it
            // with the u-axis flipped: page N+1 is "printed" on the back
            // of leaf N mirrored around the spine, so the same paper
            // position pPaper that maps to u on the front maps to (1-u)
            // on the back.
            if (hasBack > 0.5) {
                vec2 uv = sampleUVIn(vec2(pPaper, xy.y), container);
                uv.x = 1.0 - uv.x;
                fragColor = texture(backImage, uv);
            } else {
                fragColor = backColor;
            }
            // Slightly dim as it crosses vertical, brighten as it lays flat.
            float light = mix(0.82, 1.0, abs(c));
            fragColor.rgb *= light;
        } else {
            // Front face — sample page N at pPaper directly.
            fragColor = texture(image, sampleUVIn(vec2(pPaper, xy.y), container));
            // Slight darkening as the page tilts up.
            float light = mix(1.0, 0.9, s);
            fragColor.rgb *= light;
        }
    } else if (xyOnStaticSide) {
        // Soft shadow cast across the spine onto the opposite (static)
        // page. Anchored at the curling leaf's outer edge — at the spine
        // pre-vertical, then sliding outward with the leaf once it rolls
        // past the spine. Density is highest right at the anchor and
        // falls to zero at the static page's outer edge. Confined to the
        // static page's width; never bleeds past it.
        float pageWidth = max(container.z - container.x, 1.0);
        float distFromSpine =
            forward ? (spine - xy.x) : (xy.x - spine);
        float anchorDist = (progress <= 1.0) ? 0.0 : abs(c) * pageWidth;
        float extent = pageWidth - anchorDist;
        float distFromAnchor = distFromSpine - anchorDist;
        if (distFromAnchor >= 0.0 &&
            distFromSpine <= pageWidth &&
            extent > 0.5) {
            float reach = (progress <= 1.0)
                ? pageWidth * progress
                : extent;
            float t = clamp(distFromAnchor / max(reach, 1.0), 0.0, 1.0);
            float density = pow(1.0 - t, 2.0);
            float fade = 1.0 - smoothstep(1.7, 2.0, progress);
            float a = 0.5 * density * fade;
            fragColor = vec4(0.0, 0.0, 0.0, a);
        }
    } else {
        // Original side, past where the leaf currently is — let the
        // revealed next-spread-right page show through.
        fragColor = TRANSPARENT;
    }
}
