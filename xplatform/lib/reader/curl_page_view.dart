import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

/// Direction of a page-curl gesture.
enum CurlDirection {
  /// Right→left curl that reveals the next page. Triggered by a leftward
  /// drag.
  forward,

  /// Left→right curl that reveals the previous page. Triggered by a
  /// rightward drag.
  backward,
}

/// Slot a leaf occupies in the viewport. In spread mode the inner edge
/// is the spine; the host uses this to drop padding and the inner
/// corner rounding so the two cards meet flush.
enum LeafSide { single, left, right }

class LeafSideScope extends InheritedWidget {
  const LeafSideScope({super.key, required this.side, required super.child});
  final LeafSide side;
  static LeafSide of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LeafSideScope>()?.side ??
      LeafSide.single;
  @override
  bool updateShouldNotify(LeafSideScope oldWidget) => side != oldWidget.side;
}

/// External handle for [CurlPageView]. Mirrors enough of `PageController`
/// that the reader uses it as a drop-in replacement.
///
/// Page semantics: `controller.page` is the global page index, **always**.
/// In spread mode the displayed pair is `(p, p+1)` where `p` is rounded
/// down to the nearest even number — so advancing the page means `+2`,
/// not `+1`.
class CurlPageController extends ChangeNotifier {
  CurlPageController({int initialPage = 0}) : _page = initialPage;

  int _page;
  _CurlPageViewState? _attached;

  int get page => _page;
  bool get hasClients => _attached != null;

  /// Snap to [page] without playing the curl animation.
  void jumpToPage(int page) {
    _page = page;
    _attached?._snapTo(page);
    notifyListeners();
  }

  /// Play the curl animation, then settle on [page].
  Future<void> animateToPage(int page) async {
    final state = _attached;
    if (state == null) {
      _page = page;
      notifyListeners();
      return;
    }
    await state._animateTo(page);
  }
}

/// Horizontal pager with a GLSL cylindrical page-curl. The curl operates
/// on the **flipping page only** — in spread mode the page that *isn't*
/// being turned stays in the tree as a real sibling widget, not part of
/// the curl shader's source texture. That's what makes a two-page spread
/// read as two physical sheets rather than one continuous sheet with a
/// fold drawn over it.
class CurlPageView extends StatefulWidget {
  const CurlPageView({
    super.key,
    required this.controller,
    required this.pageCount,
    required this.pageBuilder,
    this.onPageChanged,
    this.onMiddleTap,
    this.spread = false,
    this.spreadGutter,
    this.commitThreshold = 0.35,
    this.commitDuration = const Duration(milliseconds: 360),
    this.springBackDuration = const Duration(milliseconds: 240),
    this.edgeTapFraction = 0.25,
    this.animationsEnabled = true,
    this.pageInsets = EdgeInsets.zero,
  });

  final CurlPageController controller;

  /// Total number of *individual* pages in the document. In spread mode
  /// the view pairs them: page `2k` on the left, `2k+1` on the right.
  final int pageCount;

  /// Builds a single page given its global index.
  final IndexedWidgetBuilder pageBuilder;

  /// Called when the *displayed* page changes. Receives the new global
  /// page index (left page in spread mode).
  final ValueChanged<int>? onPageChanged;

  /// Tap outside the edge-flip zones; the host wires this to chrome toggle.
  final VoidCallback? onMiddleTap;

  /// Fraction of viewport width on each side that flips a page on tap.
  final double edgeTapFraction;

  /// When false, tap and drag-commit snap without animating. The
  /// drag-in-progress curl stays on either way; it's direct manipulation,
  /// not animation.
  final bool animationsEnabled;

  /// Leaf-bounds to card-bounds insets. The shader uses these so the
  /// curling rectangle matches the resting card.
  final EdgeInsets pageInsets;

  /// Two-page layout. When `false`, displays one page at a time.
  final bool spread;

  /// Optional separator widget shown between the two pages in spread mode.
  final Widget? spreadGutter;

  /// Drag travel as a fraction of the *flipping leaf's* width that the
  /// user must cross before release commits to the next/previous page.
  final double commitThreshold;

  /// Duration of the "finish the curl" animation when a drag commits.
  final Duration commitDuration;

  /// Duration of the "snap back to flat" animation when a drag is released
  /// below [commitThreshold].
  final Duration springBackDuration;

  @override
  State<CurlPageView> createState() => _CurlPageViewState();
}

class _CurlPageViewState extends State<CurlPageView>
    with TickerProviderStateMixin {
  late final AnimationController _anim;
  CurlDirection? _activeDirection;

  // Touch position in the flipping leaf's local coordinate space. So
  // (origin = leaf width, pointer = 0) is a complete forward curl, etc.
  double _originX = 0;
  double _pointerX = 0;

  // Latest measured leaf width (full viewport in single mode, half in
  // spread mode). All curl math is in this coordinate space.
  // Flipping leaf's intrinsic dimensions (half the viewport in spread
  // mode, full in single mode). The curl shader treats this as the size
  // of the page texture and the bound for drag / commit math.
  double _leafWidth = 1;
  double _leafHeight = 1;

  // Total viewport width seen by the GestureDetector. In spread mode this
  // is 2× _leafWidth; in single mode it equals _leafWidth. Drag is allowed
  // anywhere in [0, _viewportWidth] so the curl can sweep across the
  // spine onto the static page's half.
  double _viewportWidth = 1;

  double? _animFrom;
  double? _animTo;
  bool _dragLocked = false;

  // Front of the flipping leaf, captured once on gesture start so the
  // shader doesn't re-rasterise the page tree every frame.
  ui.Image? _flippingSnapshot;
  final GlobalKey _flippingKey = GlobalKey();

  // Back of the flipping leaf, i.e. the page the user lands on. Sampled
  // by the shader once theta crosses vertical.
  ui.Image? _backSnapshot;
  final GlobalKey _backKey = GlobalKey();

  // Per-page RepaintBoundary keys, kept around so a page's layer stays
  // cached when it moves between the static and flipping slots.
  final Map<int, GlobalKey> _pageBoundaryKeys = {};

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)
      ..addListener(_onAnimTick);
    widget.controller._attached = this;
  }

  @override
  void didUpdateWidget(covariant CurlPageView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller._attached == this) {
        old.controller._attached = null;
      }
      widget.controller._attached = this;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _disposeSnapshot();
    if (widget.controller._attached == this) {
      widget.controller._attached = null;
    }
    super.dispose();
  }

  // --- Page index helpers -------------------------------------------------

  /// Global index of the page that flips on a forward gesture from the
  /// current view. In spread mode that's the right page of the current
  /// spread; otherwise just the current page.
  int get _forwardFlippingPage =>
      widget.spread ? widget.controller._page + 1 : widget.controller._page;

  /// Global index of the page that flips on a backward gesture.
  int get _backwardFlippingPage =>
      widget.spread
          ? widget.controller._page
          : widget.controller._page;

  /// Page revealed when the forward turn completes — the new flipping
  /// page if the user then immediately flips forward again. In single
  /// mode that's the next page; in spread mode the right page of the
  /// next spread.
  int get _afterForwardFlippingPage =>
      widget.spread ? widget.controller._page + 3 : widget.controller._page + 1;

  /// Page revealed when the backward turn completes.
  int get _afterBackwardFlippingPage =>
      widget.spread ? widget.controller._page - 2 : widget.controller._page - 1;

  /// Page revealed underneath the curling leaf — i.e. what the bottom
  /// layer should show on the flipping side.
  int? get _revealedPage {
    final dir = _activeDirection;
    if (dir == null) return null;
    if (widget.spread) {
      // Forward: page 2k+1 flips away → page 2k+3 is revealed (the new
      // right page of the next spread).
      // Backward: page 2k flips away → page 2k-2 is revealed (the new
      // left page of the previous spread).
      return dir == CurlDirection.forward
          ? _afterForwardFlippingPage
          : _afterBackwardFlippingPage;
    }
    return dir == CurlDirection.forward
        ? widget.controller._page + 1
        : widget.controller._page - 1;
  }

  bool _hasPage(int idx) => idx >= 0 && idx < widget.pageCount;

  GlobalKey _boundaryKeyFor(int idx) =>
      _pageBoundaryKeys.putIfAbsent(idx, GlobalKey.new);

  // Page printed on the back of the flipping leaf. Single mode: just
  // the next/previous page. Spread forward: the new left page of the
  // next spread (it lands where the leaf settles). Spread backward:
  // the new right page.
  int? get _backOfLeafPage {
    final dir = _activeDirection;
    if (dir == null) return null;
    final p = widget.controller._page;
    if (widget.spread) {
      return dir == CurlDirection.forward ? p + 2 : p - 1;
    }
    return dir == CurlDirection.forward ? p + 1 : p - 1;
  }

  // --- Snapshot management ------------------------------------------------

  ui.Image? _captureBoundary(GlobalKey key) {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    try {
      return boundary.toImageSync(pixelRatio: dpr);
    } catch (_) {
      return null;
    }
  }

  void _captureFlippingSnapshot() {
    _disposeSnapshot();
    _flippingSnapshot = _captureBoundary(_flippingKey);
    _backSnapshot = _captureBoundary(_backKey);
  }

  void _disposeSnapshot() {
    _flippingSnapshot?.dispose();
    _flippingSnapshot = null;
    _backSnapshot?.dispose();
    _backSnapshot = null;
  }

  // --- Controller plumbing ------------------------------------------------

  void _snapTo(int page) {
    _anim.stop();
    _activeDirection = null;
    _animFrom = null;
    _animTo = null;
    _pointerX = _originX;
    _disposeSnapshot();
    if (mounted) setState(() {});
  }

  Future<void> _animateTo(int target) async {
    if (target == widget.controller._page) return;
    if (target < 0 || target >= widget.pageCount) return;
    if (!widget.animationsEnabled) {
      final landed = widget.spread ? target & ~1 : target;
      setState(() {
        widget.controller._page = landed;
        _activeDirection = null;
        _disposeSnapshot();
      });
      widget.onPageChanged?.call(landed);
      return;
    }
    final dir = target > widget.controller._page
        ? CurlDirection.forward
        : CurlDirection.backward;
    setState(() {
      _activeDirection = dir;
      _originX = _originForDir(dir);
      _pointerX = _originX;
    });
    await WidgetsBinding.instance.endOfFrame;
    _captureFlippingSnapshot();
    final dest = _commitDestForDir(dir);
    await _tweenPointerTo(dest, widget.commitDuration);
    if (!mounted) return;
    setState(() {
      widget.controller._page = widget.spread ? target & ~1 : target;
      _activeDirection = null;
      _pointerX = _originX;
      _disposeSnapshot();
    });
    widget.onPageChanged?.call(widget.controller._page);
  }

  // Spine x of the flipping leaf. The fold emerges from this edge and
  // tracks the finger toward the opposite side.
  double _originForDir(CurlDirection dir) =>
      dir == CurlDirection.forward ? _cardRect().right : _cardRect().left;

  /// Where the pointer needs to land for a full-flip (progress = 2.0).
  /// Since `progress = (origin − pointer)·sign / pageWidth` and we want
  /// progress = 2.0, pointer = origin − 2·pageWidth·sign — which may
  /// well be off-screen if the user touched anywhere except the far
  /// edge. That's fine; the shader clamps progress and the user never
  /// physically interacts with the off-screen part of the animation.
  double _commitDestForDir(CurlDirection dir) {
    final pageW = _cardRect().width;
    return dir == CurlDirection.forward
        ? _originX - 2 * pageW
        : _originX + 2 * pageW;
  }

  // Insets adjusted per side. The spine edge gets zero inset in spread
  // mode so the two cards meet flush.
  EdgeInsets _effectivePageInsets(LeafSide side) {
    final p = widget.pageInsets;
    switch (side) {
      case LeafSide.single:
        return p;
      case LeafSide.left:
        return EdgeInsets.fromLTRB(p.left, p.top, 0, p.bottom);
      case LeafSide.right:
        return EdgeInsets.fromLTRB(0, p.top, p.right, p.bottom);
    }
  }

  // Card rect for a leaf at [side] in viewport coords. Right-side
  // leaves anchor at x=_leafWidth, everything else at x=0.
  Rect _cardRectForSide(LeafSide side) {
    final p = _effectivePageInsets(side);
    final leafX = side == LeafSide.right ? _leafWidth : 0.0;
    return Rect.fromLTRB(
      leafX + p.left,
      p.top,
      leafX + _leafWidth - p.right,
      _leafHeight - p.bottom,
    );
  }

  // Side of the currently-flipping leaf. Single mode is always single.
  LeafSide _flippingSide() {
    if (!widget.spread) return LeafSide.single;
    return _activeDirection == CurlDirection.forward
        ? LeafSide.right
        : LeafSide.left;
  }

  LeafSide _sideForIdx(int idx) {
    if (!widget.spread) return LeafSide.single;
    return idx.isEven ? LeafSide.left : LeafSide.right;
  }

  // Card rect of the flipping leaf; feeds the shader's container uniform.
  Rect _cardRect() => _cardRectForSide(_flippingSide());

  // --- Drag handling ------------------------------------------------------

  void _onDragStart(DragStartDetails d) {
    if (_dragLocked) return;
    _anim.stop();
    _animFrom = null;
    _animTo = null;
    _pointerX = d.localPosition.dx;
    _originX = _pointerX;
    _activeDirection = null;
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_dragLocked) return;
    _pointerX = d.localPosition.dx;
    if (_activeDirection == null) {
      if (_pointerX < _originX - 4) {
        _activeDirection = CurlDirection.forward;
      } else if (_pointerX > _originX + 4) {
        _activeDirection = CurlDirection.backward;
      }
      if (_activeDirection != null) {
        // origin stays at the touch start position — progress is the
        // actual finger travel, not absolute viewport-x. That way the
        // page begins at zero rotation no matter where on the leaf the
        // user grabbed.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _activeDirection == null) return;
          _captureFlippingSnapshot();
          setState(() {});
        });
      }
    }
    _pointerX = _pointerX.clamp(0.0, _viewportWidth);
    setState(() {});
  }

  void _onTapUp(TapUpDetails d) {
    if (_dragLocked) return;
    final x = d.localPosition.dx;
    final edge = _viewportWidth * widget.edgeTapFraction;
    final step = widget.spread ? 2 : 1;
    if (x < edge) {
      final target = widget.controller._page - step;
      if (_hasPage(target)) {
        _animateTo(target);
        return;
      }
    } else if (x > _viewportWidth - edge) {
      final target = widget.controller._page + step;
      final flippingTarget = widget.spread ? target + 1 : target;
      if (_hasPage(flippingTarget) || _hasPage(target)) {
        _animateTo(target);
        return;
      }
    }
    widget.onMiddleTap?.call();
  }

  void _onDragEnd(DragEndDetails d) {
    final dir = _activeDirection;
    if (dir == null) {
      setState(() {});
      return;
    }
    // Commit threshold is measured against the visible card, not the
    // leaf or viewport, so it still fires at 35% of the page when the
    // user grabbed the padding or dragged across the spine.
    final dxFraction = (_originX - _pointerX).abs() /
        _cardRect().width.clamp(1.0, double.infinity);
    final canCommit = dir == CurlDirection.forward
        ? _hasPage(_forwardFlippingPage + 1)
        : _hasPage(_backwardFlippingPage - 1);
    if (canCommit && dxFraction >= widget.commitThreshold) {
      final newLeftPage = dir == CurlDirection.forward
          ? widget.controller._page + (widget.spread ? 2 : 1)
          : widget.controller._page - (widget.spread ? 2 : 1);
      if (!widget.animationsEnabled) {
        setState(() {
          widget.controller._page =
              widget.spread ? newLeftPage & ~1 : newLeftPage;
          _activeDirection = null;
          _pointerX = _originX;
          _disposeSnapshot();
        });
        widget.onPageChanged?.call(widget.controller._page);
        return;
      }
      final dest = _commitDestForDir(dir);
      _dragLocked = true;
      _tweenPointerTo(dest, widget.commitDuration).then((_) {
        if (!mounted) return;
        setState(() {
          widget.controller._page =
              widget.spread ? newLeftPage & ~1 : newLeftPage;
          _activeDirection = null;
          _pointerX = _originX;
          _disposeSnapshot();
        });
        widget.onPageChanged?.call(widget.controller._page);
        _dragLocked = false;
      });
    } else {
      if (!widget.animationsEnabled) {
        setState(() {
          _pointerX = _originX;
          _activeDirection = null;
          _disposeSnapshot();
        });
        return;
      }
      _dragLocked = true;
      _tweenPointerTo(_originX, widget.springBackDuration).then((_) {
        if (!mounted) return;
        setState(() {
          _activeDirection = null;
          _disposeSnapshot();
        });
        _dragLocked = false;
      });
    }
  }

  // --- Animation plumbing -------------------------------------------------

  Future<void> _tweenPointerTo(double dest, Duration duration) {
    _animFrom = _pointerX;
    _animTo = dest;
    _anim.duration = duration;
    return _anim.forward(from: 0);
  }

  void _onAnimTick() {
    final from = _animFrom;
    final to = _animTo;
    if (from == null || to == null) return;
    final t = Curves.easeOut.transform(_anim.value);
    _pointerX = from + (to - from) * t;
    if (mounted) setState(() {});
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dir = _activeDirection;
    final snapshot = _flippingSnapshot;
    final brightness = Theme.of(context).brightness;
    final backColor = brightness == Brightness.dark
        ? const Color.fromARGB(255, 27, 24, 21)
        : const Color.fromARGB(255, 244, 239, 230);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        _viewportWidth = viewportWidth;
        _leafWidth = widget.spread ? viewportWidth / 2 : viewportWidth;
        _leafHeight = viewportHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onTapUp: _onTapUp,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              // Hidden back-leaf goes BEHIND the base layout so the
              // static / flipping card covers it visually. It still
              // paints (so its RepaintBoundary captures), which we need
              // for the curl shader's back-face sampler.
              ..._buildHiddenBackLeafLayer(),
              ..._buildBaseLayout(),
              ..._buildRevealLayer(dir),
              if (dir != null && snapshot != null)
                _buildCurlLayer(
                  dir: dir,
                  snapshot: snapshot,
                  backSnapshot: _backSnapshot,
                  backColor: backColor,
                ),
            ],
          ),
        );
      },
    );
  }

  /// The page content at rest. In spread mode that's two side-by-side
  /// pages with the gutter between them; in single mode just one. These
  /// stay in the tree during a curl (the *static* side keeps showing
  /// uninterrupted, the *flipping* side gets covered by the curl layer).
  List<Widget> _buildBaseLayout() {
    final page = widget.controller._page;
    final dir = _activeDirection;

    if (!widget.spread) {
      return [
        Positioned.fill(
          child: _hostedPage(
            page,
            key: _flippingKey,
            captureKey: _boundaryKeyFor(page),
          ),
        ),
      ];
    }

    final leftIdx = page & ~1;
    final rightIdx = leftIdx + 1;

    final flippingIdx = dir == CurlDirection.backward ? leftIdx : rightIdx;
    final staticIdx = dir == CurlDirection.backward ? rightIdx : leftIdx;

    return [
      Positioned.fromRect(
        rect: Rect.fromLTWH(
          _sideForIdx(staticIdx) == LeafSide.right ? _leafWidth : 0,
          0,
          _leafWidth,
          _leafHeight,
        ),
        child: _hasPage(staticIdx)
            ? _hostedPage(staticIdx,
                key: ValueKey('static-$staticIdx'),
                captureKey: _boundaryKeyFor(staticIdx),
                side: _sideForIdx(staticIdx))
            : const SizedBox.shrink(),
      ),
      Positioned.fromRect(
        rect: Rect.fromLTWH(
          _sideForIdx(flippingIdx) == LeafSide.right ? _leafWidth : 0,
          0,
          _leafWidth,
          _leafHeight,
        ),
        child: _hasPage(flippingIdx)
            ? _hostedPage(flippingIdx,
                key: _flippingKey,
                captureKey: _boundaryKeyFor(flippingIdx),
                side: _sideForIdx(flippingIdx))
            : const SizedBox.shrink(),
      ),
    ];
  }

  // Two nested RepaintBoundaries per leaf: an inner one keyed by page
  // index (so the layer stays cached when the page moves between slots)
  // and an outer one keyed by role (_flippingKey / "static-N") so the
  // gesture code can grab "whatever's currently flipping". Side insets
  // are applied as outer Padding so the boundaries tightly bound the
  // card -- the snapshot then matches the shader's container rect.
  Widget _hostedPage(
    int idx, {
    required Key key,
    required GlobalKey captureKey,
    LeafSide side = LeafSide.single,
  }) {
    final boundaries = RepaintBoundary(
      key: key,
      child: RepaintBoundary(
        key: captureKey,
        child: LeafSideScope(
          side: side,
          // The Builder is here so pageBuilder's BuildContext is BELOW
          // the LeafSideScope; without it LeafSideScope.of() can't find
          // the scope.
          child: Builder(builder: (ctx) => widget.pageBuilder(ctx, idx)),
        ),
      ),
    );
    final insets = _effectivePageInsets(side);
    final padded =
        insets == EdgeInsets.zero ? boundaries : Padding(padding: insets, child: boundaries);
    return _clipShadowToSide(padded, side);
  }

  // Clips a leaf's painting so its drop shadow stops at the spine.
  // Without this the right leaf (drawn on top) casts a visible shadow
  // onto the left leaf's inner edge but not vice-versa, making the
  // left page look like it's lower in 3-space.
  Widget _clipShadowToSide(Widget child, LeafSide side) {
    if (side == LeafSide.single) return child;
    return ClipRect(
      clipper: _SpineSideClipper(side: side),
      child: child,
    );
  }

  // The page that gets revealed underneath the curl. Single mode: fills
  // the viewport. Spread mode: clipped to the flipping side; the static
  // page is already drawn on the other half.
  List<Widget> _buildRevealLayer(CurlDirection? dir) {
    if (dir == null) return const [];
    final idx = _revealedPage;
    if (idx == null || !_hasPage(idx)) return const [];
    final side = _sideForIdx(idx);
    final insets = _effectivePageInsets(side);
    Widget revealCard = RepaintBoundary(
      child: LeafSideScope(
        side: side,
        child: Builder(builder: (ctx) => widget.pageBuilder(ctx, idx)),
      ),
    );
    if (insets != EdgeInsets.zero) {
      revealCard = Padding(padding: insets, child: revealCard);
    }
    revealCard = _clipShadowToSide(revealCard, side);
    if (!widget.spread) {
      return [Positioned.fill(child: revealCard)];
    }
    return [
      Positioned.fromRect(
        rect: Rect.fromLTWH(
          side == LeafSide.right ? _leafWidth : 0,
          0,
          _leafWidth,
          _leafHeight,
        ),
        child: revealCard,
      ),
    ];
  }

  // Card-sized RepaintBoundary holding the page on the back of the
  // flipping leaf. Sits behind the base layout so the static / flipping
  // card covers it visually, but its layer still paints (Opacity(0)
  // would short-circuit paint and leave the snapshot empty).
  List<Widget> _buildHiddenBackLeafLayer() {
    final backIdx = _backOfLeafPage;
    if (backIdx == null || !_hasPage(backIdx)) return const [];
    final side = _sideForIdx(backIdx);
    return [
      Positioned.fromRect(
        rect: _cardRectForSide(side),
        child: IgnorePointer(
          child: RepaintBoundary(
            key: _backKey,
            child: LeafSideScope(
              side: side,
              child: Builder(
                builder: (ctx) => widget.pageBuilder(ctx, backIdx),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildCurlLayer({
    required CurlDirection dir,
    required ui.Image snapshot,
    required ui.Image? backSnapshot,
    required Color backColor,
  }) {
    // Spans the full viewport. The shader emits transparent outside the
    // container rect so the static page sibling shows through, except in
    // the curl zone where the cylinder has rolled past the spine.
    return Positioned.fill(
      child: _CurlLayer(
        snapshot: snapshot,
        backSnapshot: backSnapshot,
        pointerX: _pointerX,
        originX: _originX,
        direction: dir,
        backColor: backColor,
        container: _cardRect(),
      ),
    );
  }
}

// Clips a leaf's painting so its drop shadow stops at the spine edge.
// Outside edges get a margin so the soft shadow still renders.
class _SpineSideClipper extends CustomClipper<Rect> {
  const _SpineSideClipper({required this.side});
  final LeafSide side;
  static const double extra = 30;

  @override
  Rect getClip(Size size) {
    switch (side) {
      case LeafSide.single:
        return Rect.fromLTRB(
            -extra, -extra, size.width + extra, size.height + extra);
      case LeafSide.left:
        // Spine on the right: clip flush there, leave room on the other sides.
        return Rect.fromLTRB(-extra, -extra, size.width, size.height + extra);
      case LeafSide.right:
        // Spine on the left: clip flush at x=0.
        return Rect.fromLTRB(0, -extra, size.width + extra, size.height + extra);
    }
  }

  @override
  bool shouldReclip(_SpineSideClipper old) => old.side != side;
}

class _CurlLayer extends StatelessWidget {
  const _CurlLayer({
    required this.snapshot,
    required this.backSnapshot,
    required this.pointerX,
    required this.originX,
    required this.direction,
    required this.backColor,
    required this.container,
  });

  final ui.Image snapshot;
  final ui.Image? backSnapshot;
  final double pointerX;
  final double originX;
  final CurlDirection direction;
  final Color backColor;
  final Rect container;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      (context, shader, _) {
        return CustomPaint(
          painter: _CurlPainter(
            snapshot: snapshot,
            backSnapshot: backSnapshot,
            shader: shader,
            pointerX: pointerX,
            originX: originX,
            direction: direction,
            backColor: backColor,
            container: container,
          ),
          size: Size.infinite,
        );
      },
      assetKey: 'shaders/page_curl.frag',
    );
  }
}

class _CurlPainter extends CustomPainter {
  _CurlPainter({
    required this.snapshot,
    required this.backSnapshot,
    required this.shader,
    required this.pointerX,
    required this.originX,
    required this.direction,
    required this.backColor,
    required this.container,
  });

  final ui.Image snapshot;
  final ui.Image? backSnapshot;
  final ui.FragmentShader shader;
  final double pointerX;
  final double originX;
  final CurlDirection direction;
  final Color backColor;
  final Rect container;

  @override
  void paint(Canvas canvas, Size size) {
    final hasBack = backSnapshot != null;
    shader.setFloatUniforms((u) {
      // Uniforms in declaration order — see shaders/page_curl.frag.
      u.setSize(size);
      u.setFloat(pointerX);
      u.setFloat(originX);
      u.setFloats(
          [container.left, container.top, container.right, container.bottom]);
      u.setFloat(0.0);
      u.setFloat(direction == CurlDirection.forward ? 0.0 : 1.0);
      u.setFloat(backColor.r);
      u.setFloat(backColor.g);
      u.setFloat(backColor.b);
      u.setFloat(backColor.a);
      u.setFloat(hasBack ? 1.0 : 0.0);
    });
    shader.setImageSampler(0, snapshot);
    // Sampler 1 must always be bound; the hasBack uniform decides
    // whether the shader actually reads it. Fall back to the front
    // snapshot when there's no real back yet.
    shader.setImageSampler(1, backSnapshot ?? snapshot);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _CurlPainter old) =>
      old.snapshot != snapshot ||
      old.backSnapshot != backSnapshot ||
      old.pointerX != pointerX ||
      old.originX != originX ||
      old.direction != direction ||
      old.backColor != backColor ||
      old.container != container;
}
