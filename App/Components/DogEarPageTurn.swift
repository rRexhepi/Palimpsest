import SwiftUI
import InkAndEchoCore

/// Horizontal page-turn overlay with a small dog-ear corner peel. The
/// dominant motion is a vertical-fold horizontal sweep — the lifted leaf
/// covers the right (forward) or left (backward) strip of the page as the
/// fold walks across. On top of that strip, a small triangular peel at the
/// outer-top corner reads as the corner the reader pinched to start the
/// turn, with its own fold line and a slightly different shade so it sits
/// "above" the main flap.
///
/// Earlier iterations were either a pure diagonal corner peel (read as a
/// card flip) or a pure horizontal sweep (read as a curtain). Combining
/// the two captures both the horizontal motion of a real page turn AND
/// the corner-pinch start that paper actually does.
struct DogEarPageTurn: View {
    var progress: Double
    var direction: Direction
    let colorScheme: ColorScheme

    enum Direction {
        case forward   // sweep from right edge toward the spine (next page)
        case backward  // sweep from left edge outward (previous page)
    }

    var body: some View {
        GeometryReader { geo in
            let p = max(0.0001, min(1.0, progress))
            let layout = layoutPoints(width: geo.size.width, height: geo.size.height, progress: p)

            ZStack {
                // 1. Cast shadow just behind the fold on the side that
                // hasn't been lifted yet — implies depth above the page.
                shadowPath(layout: layout, geo: geo.size)
                    .fill(shadowColor)
                    .blur(radius: 8)
                    .clipShape(Rectangle().path(in: CGRect(origin: .zero, size: geo.size)))

                // 2. Main horizontal flap — the lifted leaf showing back of
                // paper. The polygon clips out the top-outer corner so the
                // dog-ear triangle sits cleanly on top of the cut.
                mainFlapPath(layout: layout, geo: geo.size)
                    .fill(
                        LinearGradient(
                            stops: paperGradientStops,
                            startPoint: gradientStart,
                            endPoint: gradientEnd
                        )
                    )
                    .overlay(
                        mainFlapPath(layout: layout, geo: geo.size)
                            .stroke(flapBorderColor, style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
                    )

                // 3. Dog-ear triangle at the outer-top corner — the
                // "pinched" corner the reader grabbed first. Slightly
                // darker than the main flap so it reads as one layer up.
                dogEarPath(layout: layout)
                    .fill(dogEarColor)
                    .overlay(
                        dogEarPath(layout: layout)
                            .stroke(flapBorderColor, style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
                    )

                // 4a. Specular highlight along the main vertical fold.
                Path { path in
                    path.move(to: CGPoint(x: layout.foldX, y: layout.dogEarSize))
                    path.addLine(to: CGPoint(x: layout.foldX, y: geo.size.height))
                }
                .stroke(specularColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                // 4b. Specular along the dog-ear fold (the diagonal crease
                // separating the corner peel from the main flap).
                Path { path in
                    path.move(to: CGPoint(x: layout.dogEarFoldTop, y: 0))
                    path.addLine(to: CGPoint(x: layout.dogEarFoldSide, y: layout.dogEarSize))
                }
                .stroke(specularColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private struct LayoutPoints {
        /// X position of the main vertical fold line.
        let foldX: CGFloat
        /// Outer edge of the lifted leaf (the page edge being lifted).
        let outerEdgeX: CGFloat
        /// Height of the dog-ear corner peel — also its width along the top.
        let dogEarSize: CGFloat
        /// Top-edge x position where the dog-ear fold meets the page top.
        let dogEarFoldTop: CGFloat
        /// Side-edge x position where the dog-ear fold meets the outer edge
        /// of the leaf (the fold line drops vertically from here).
        let dogEarFoldSide: CGFloat
    }

    private func layoutPoints(width w: CGFloat, height h: CGFloat, progress p: CGFloat) -> LayoutPoints {
        let leafWidth: CGFloat
        let foldX: CGFloat
        let outerEdgeX: CGFloat
        switch direction {
        case .forward:
            foldX = w * (1 - p)
            outerEdgeX = w
            leafWidth = w - foldX
        case .backward:
            foldX = w * p
            outerEdgeX = 0
            leafWidth = foldX
        }
        // Dog-ear scales with the lifted-leaf width so it never overflows
        // a small flap, but caps at 32pt so it doesn't dominate at the end
        // of the turn when the leaf is wide.
        let dogEarSize = min(max(0, leafWidth * 0.32), 32)
        let dogEarFoldTop: CGFloat
        let dogEarFoldSide: CGFloat
        switch direction {
        case .forward:
            // Dog-ear at the top-right corner of the leaf. Fold runs from
            // (outer-dogEarSize, 0) on the top edge to (outer, dogEarSize)
            // on the right edge.
            dogEarFoldTop = outerEdgeX - dogEarSize
            dogEarFoldSide = outerEdgeX
        case .backward:
            // Mirror: dog-ear at the top-left corner.
            dogEarFoldTop = outerEdgeX + dogEarSize
            dogEarFoldSide = outerEdgeX
        }
        return LayoutPoints(
            foldX: foldX,
            outerEdgeX: outerEdgeX,
            dogEarSize: dogEarSize,
            dogEarFoldTop: dogEarFoldTop,
            dogEarFoldSide: dogEarFoldSide
        )
    }

    /// The main lifted leaf — a rectangle from foldX to outerEdge, with
    /// the top-outer corner clipped along the dog-ear fold.
    private func mainFlapPath(layout: LayoutPoints, geo: CGSize) -> Path {
        Path { path in
            switch direction {
            case .forward:
                // Walk: top-fold → top-right (minus dog-ear) → side-fold →
                // bottom-right → bottom-left.
                path.move(to: CGPoint(x: layout.foldX, y: 0))
                path.addLine(to: CGPoint(x: layout.dogEarFoldTop, y: 0))
                path.addLine(to: CGPoint(x: layout.dogEarFoldSide, y: layout.dogEarSize))
                path.addLine(to: CGPoint(x: layout.outerEdgeX, y: geo.height))
                path.addLine(to: CGPoint(x: layout.foldX, y: geo.height))
                path.closeSubpath()
            case .backward:
                // Mirror: top-left (minus dog-ear) → top-fold → bottom-fold
                // → bottom-left → side-fold.
                path.move(to: CGPoint(x: layout.dogEarFoldTop, y: 0))
                path.addLine(to: CGPoint(x: layout.foldX, y: 0))
                path.addLine(to: CGPoint(x: layout.foldX, y: geo.height))
                path.addLine(to: CGPoint(x: layout.outerEdgeX, y: geo.height))
                path.addLine(to: CGPoint(x: layout.dogEarFoldSide, y: layout.dogEarSize))
                path.closeSubpath()
            }
        }
    }

    /// Triangular dog-ear corner peel that sits on top of the main flap.
    private func dogEarPath(layout: LayoutPoints) -> Path {
        Path { path in
            switch direction {
            case .forward:
                path.move(to: CGPoint(x: layout.dogEarFoldTop, y: 0))
                path.addLine(to: CGPoint(x: layout.outerEdgeX, y: 0))
                path.addLine(to: CGPoint(x: layout.dogEarFoldSide, y: layout.dogEarSize))
            case .backward:
                path.move(to: CGPoint(x: layout.outerEdgeX, y: 0))
                path.addLine(to: CGPoint(x: layout.dogEarFoldTop, y: 0))
                path.addLine(to: CGPoint(x: layout.dogEarFoldSide, y: layout.dogEarSize))
            }
            path.closeSubpath()
        }
    }

    /// Soft shadow strip just behind the fold on the unrevealed side.
    private func shadowPath(layout: LayoutPoints, geo: CGSize) -> Path {
        let shadowWidth: CGFloat = 22
        let rect: CGRect
        switch direction {
        case .forward:
            rect = CGRect(
                x: max(0, layout.foldX - shadowWidth),
                y: 0,
                width: shadowWidth,
                height: geo.height
            )
        case .backward:
            rect = CGRect(
                x: layout.foldX,
                y: 0,
                width: shadowWidth,
                height: geo.height
            )
        }
        return Path(rect)
    }

    private var paperGradientStops: [Gradient.Stop] {
        if colorScheme == .dark {
            return [
                .init(color: Color(red: 42/255, green: 37/255, blue: 32/255), location: 0.0),
                .init(color: Color(red: 33/255, green: 29/255, blue: 24/255), location: 0.55),
                .init(color: Color(red: 21/255, green: 18/255, blue: 15/255), location: 1.0),
            ]
        }
        return [
            .init(color: Color(red: 252/255, green: 248/255, blue: 236/255), location: 0.0),
            .init(color: Color(red: 244/255, green: 239/255, blue: 230/255), location: 0.55),
            .init(color: Color(red: 237/255, green: 232/255, blue: 221/255), location: 1.0),
        ]
    }

    private var gradientStart: UnitPoint {
        direction == .forward ? .leading : .trailing
    }

    private var gradientEnd: UnitPoint {
        direction == .forward ? .trailing : .leading
    }

    private var flapBorderColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color(red: 31/255, green: 26/255, blue: 20/255).opacity(0.10)
    }

    /// Dog-ear corner shade — slightly darker than the main flap so the
    /// peel reads as a layer above. Tuned per scheme so it stays a "deeper
    /// paper" tone rather than a black smudge.
    private var dogEarColor: Color {
        colorScheme == .dark
            ? Color(red: 28/255, green: 24/255, blue: 20/255)
            : Color(red: 226/255, green: 219/255, blue: 203/255)
    }

    private var specularColor: Color {
        colorScheme == .dark
            ? Color(red: 255/255, green: 247/255, blue: 228/255).opacity(0.22)
            : Color(red: 255/255, green: 247/255, blue: 228/255).opacity(0.95)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color(red: 31/255, green: 26/255, blue: 20/255).opacity(0.28)
    }
}
