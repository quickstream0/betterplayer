import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:flutter/material.dart';
import 'dart:async';

/// Configuration for gesture-based controls
class BetterPlayerGestureConfiguration {
  const BetterPlayerGestureConfiguration({
    this.enableVolumeSwipe = true,
    this.enableBrightnessSwipe = true,
    this.enableSeekSwipe = true,
    this.enableDoubleTapSeek = true,
    this.volumeSwipeSensitivity = 0.5,
    this.brightnessSwipeSensitivity = 0.5,
    this.seekSwipeSensitivity = 1.0,
    this.minimumSwipeDistance = 10.0,
    this.feedbackDuration = const Duration(milliseconds: 800),
    this.swipeAreaWidthPercentage = 0.25, // 0.25 (25% each side)
  });

  /// Enable volume control via vertical swipe on right side
  final bool enableVolumeSwipe;

  /// Enable brightness control via vertical swipe on left side
  final bool enableBrightnessSwipe;

  /// Enable seek control via horizontal swipe
  final bool enableSeekSwipe;

  /// Enable seek control via double tap
  final bool enableDoubleTapSeek;

  /// Volume swipe sensitivity (0.1 - 2.0)
  final double volumeSwipeSensitivity;

  /// Brightness swipe sensitivity (0.1 - 2.0)
  final double brightnessSwipeSensitivity;

  /// Seek swipe sensitivity (0.1 - 2.0)
  final double seekSwipeSensitivity;

  /// Minimum distance to trigger swipe gesture
  final double minimumSwipeDistance;

  /// Duration to show feedback overlay
  final Duration feedbackDuration;

  /// Width percentage of left/right swipe areas (0.2 - 0.5)
  final double swipeAreaWidthPercentage;
}

/// Types of gesture feedback
enum GestureFeedbackType { volume, brightness, seekForward, seekBackward }

/// Widget that handles gesture-based controls for video player
class BetterPlayerGestureHandler extends StatefulWidget {
  const BetterPlayerGestureHandler({
    super.key,
    required this.child,
    required this.configuration,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onSeek,
    required this.onSwipeAreaTap,
    required this.currentVolume,
    required this.currentBrightness,
    this.controlsVisible = true, // Whether controls are currently visible
  });

  final Widget child;
  final BetterPlayerGestureConfiguration configuration;
  final Function(double volume) onVolumeChanged;
  final Function(double brightness) onBrightnessChanged;
  final Function(Duration position) onSeek;
  final Function onSwipeAreaTap;
  final double currentVolume;
  final double currentBrightness;
  final bool controlsVisible;

  @override
  State<BetterPlayerGestureHandler> createState() => _BetterPlayerGestureHandlerState();
}

class _BetterPlayerGestureHandlerState extends State<BetterPlayerGestureHandler> {
  bool _isGestureActive = false;
  GestureFeedbackType? _currentGesture;
  double _gestureValue = 0.0;
  Offset? _dragStartPosition;
  double _initialValue = 0.0;
  Timer? _feedbackTimer;

  // Track if we've moved enough to be considered a drag (not a tap)
  bool _hasMovedEnough = false;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details, bool isLeftSide) {
    final config = widget.configuration;

    if (isLeftSide && !config.enableBrightnessSwipe) return;
    if (!isLeftSide && !config.enableVolumeSwipe) return;

    // DEBUG: Log gesture detection
    BetterPlayerUtils.log(
      '🎯 BetterPlayer Gesture: Vertical drag started on ${isLeftSide ? "LEFT (Brightness)" : "RIGHT (Volume)"} side',
    );

    _dragStartPosition = details.localPosition;
    _hasMovedEnough = false; // Don't activate gesture until we move enough

    // CRITICAL FIX: Get the CURRENT value from widget props (which were updated by previous gestures)
    if (isLeftSide) {
      _currentGesture = GestureFeedbackType.brightness;
      _initialValue = widget.currentBrightness;
      BetterPlayerUtils.log('🎯 Starting brightness gesture from: ${_initialValue.toStringAsFixed(2)}');
    } else {
      _currentGesture = GestureFeedbackType.volume;
      _initialValue = widget.currentVolume;
      BetterPlayerUtils.log('🎯 Starting volume gesture from: ${_initialValue.toStringAsFixed(2)}');
    }

    // DON'T call setState or set _isGestureActive yet - wait for actual movement
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, bool isLeftSide, double screenHeight) {
    if (_dragStartPosition == null) return;

    final config = widget.configuration;
    // FIX: Correct direction - swipe UP should increase, swipe DOWN should decrease
    final double delta = details.localPosition.dy - _dragStartPosition!.dy;

    // Check if we've moved enough to be considered a real drag (not a tap)
    if (!_hasMovedEnough) {
      if (delta.abs() < config.minimumSwipeDistance) {
        return; // Still below threshold, could be a tap
      }
      // We've moved enough - activate the gesture now!
      _hasMovedEnough = true;
      _isGestureActive = true;
      _gestureValue = _initialValue; // Start from initial value
      setState(() {});
    }

    if (!_isGestureActive) return;

    // Cancel any pending hide timer while actively dragging
    _feedbackTimer?.cancel();

    // DEBUG: Log gesture value
    BetterPlayerUtils.log(
      '🎯 BetterPlayer Gesture: ${isLeftSide ? "Brightness" : "Volume"} delta=$delta, initial=$_initialValue',
    );

    final double sensitivity = isLeftSide ? config.brightnessSwipeSensitivity : config.volumeSwipeSensitivity;

    // Negative delta = swipe UP = INCREASE value
    // Positive delta = swipe DOWN = DECREASE value
    final double normalizedDelta = -(delta / screenHeight) * sensitivity;
    final double newValue = (_initialValue + normalizedDelta).clamp(0.0, 1.0);

    setState(() {
      _gestureValue = newValue;
    });

    if (isLeftSide) {
      widget.onBrightnessChanged(newValue);
    } else {
      widget.onVolumeChanged(newValue);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartPosition = null;
    _hasMovedEnough = false;

    // Only hide feedback if gesture was actually activated
    if (_isGestureActive) {
      _hideFeedbackAfterDelay();
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.configuration.enableSeekSwipe) return;

    BetterPlayerUtils.log('🎯 BetterPlayer Gesture: Horizontal drag started (Seek)');

    _dragStartPosition = details.localPosition;
    _hasMovedEnough = false; // Don't activate until we move enough
    _currentGesture = GestureFeedbackType.seekForward; // Temporary
    _initialValue = 0.0;

    // DON'T call setState or set _isGestureActive yet - wait for actual movement
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (_dragStartPosition == null) return;

    final config = widget.configuration;
    final double delta = details.localPosition.dx - _dragStartPosition!.dx;

    // Check if we've moved enough to be considered a real drag (not a tap)
    if (!_hasMovedEnough) {
      if (delta.abs() < config.minimumSwipeDistance) {
        return; // Still below threshold, could be a tap
      }
      // We've moved enough - activate the gesture now!
      _hasMovedEnough = true;
      _isGestureActive = true;
      _gestureValue = 0.0;
      setState(() {});
    }

    if (!_isGestureActive) return;

    // Cancel any pending hide timer while actively dragging
    _feedbackTimer?.cancel();

    final double sensitivity = config.seekSwipeSensitivity;
    final double normalizedDelta = (delta / screenWidth) * sensitivity;

    setState(() {
      _gestureValue = normalizedDelta * 100; // Convert to seconds
      _currentGesture = normalizedDelta > 0 ? GestureFeedbackType.seekForward : GestureFeedbackType.seekBackward;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // Only perform seek if gesture was actually activated
    if (_isGestureActive && _gestureValue != 0) {
      final seekDuration = Duration(seconds: _gestureValue.abs().round());
      widget.onSeek(seekDuration);
    }

    _dragStartPosition = null;
    _hasMovedEnough = false;

    // Only hide feedback if gesture was actually activated
    if (_isGestureActive) {
      _hideFeedbackAfterDelay();
    }
  }

  void _onLeftSwipeAreaDoubleTap() {
    if (!widget.configuration.enableDoubleTapSeek) return;
    _isGestureActive = true;
    _gestureValue = -5;
    _currentGesture = GestureFeedbackType.seekBackward;
    setState(() {});
    widget.onSeek(Duration(seconds: _gestureValue.toInt()));
    if (_isGestureActive) {
      _hideFeedbackAfterDelay();
    }
  }

  void _onRightSwipeAreaDoubleTap() {
    if (!widget.configuration.enableDoubleTapSeek) return;
    _isGestureActive = true;
    _gestureValue = 5;
    _currentGesture = GestureFeedbackType.seekForward;
    setState(() {});
    widget.onSeek(Duration(seconds: _gestureValue.toInt()));
    if (_isGestureActive) {
      _hideFeedbackAfterDelay();
    }
  }

  void _hideFeedbackAfterDelay() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(widget.configuration.feedbackDuration, () {
      if (mounted) {
        setState(() {
          _isGestureActive = false;
          _currentGesture = null;
        });
      }
    });
  }

  void _onSwipeAreaTap() {
    widget.onSwipeAreaTap;
  }

  @override
  Widget build(BuildContext context) {
    BetterPlayerUtils.log('🎯 BetterPlayer: Building GestureHandler widget');
    final size = MediaQuery.of(context).size;
    final swipeAreaWidth = size.width * widget.configuration.swipeAreaWidthPercentage;

    // Define safe zones to avoid blocking control bars
    // Top bar is typically 50-80px, bottom bar is 80-100px
    const double topSafeZone = 80.0;
    const double bottomSafeZone = 90.0;

    return Stack(
      children: [
        // Original child (controls) - put FIRST so gesture zones can overlay
        widget.child,

        // Left side - Brightness control (only active when controls are hidden)
        if (widget.configuration.enableBrightnessSwipe)
          Positioned(
            left: 0,
            top: topSafeZone, // Don't cover top bar
            bottom: bottomSafeZone, // Don't cover bottom bar
            width: swipeAreaWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent, // Let taps pass through while catching drags
              onVerticalDragStart: !widget.controlsVisible ? (details) => _onVerticalDragStart(details, true) : null,
              onVerticalDragUpdate: !widget.controlsVisible
                  ? (details) => _onVerticalDragUpdate(details, true, size.height)
                  : null,
              onVerticalDragEnd: !widget.controlsVisible ? _onVerticalDragEnd : null,
              onDoubleTap: !widget.controlsVisible ? _onLeftSwipeAreaDoubleTap : null,
              onTap: _onSwipeAreaTap,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Right side - Volume control (only active when controls are hidden)
        if (widget.configuration.enableVolumeSwipe)
          Positioned(
            right: 0,
            top: topSafeZone, // Don't cover top bar
            bottom: bottomSafeZone, // Don't cover bottom bar
            width: swipeAreaWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent, // Let taps pass through while catching drags
              onVerticalDragStart: !widget.controlsVisible ? (details) => _onVerticalDragStart(details, false) : null,
              onVerticalDragUpdate: !widget.controlsVisible
                  ? (details) => _onVerticalDragUpdate(details, false, size.height)
                  : null,
              onVerticalDragEnd: !widget.controlsVisible ? _onVerticalDragEnd : null,
              onDoubleTap: !widget.controlsVisible ? _onRightSwipeAreaDoubleTap : null,
              onTap: _onSwipeAreaTap,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Bottom center - Seek control (only active when controls are hidden)
        // Small horizontal strip at the bottom for seek gestures
        if (widget.configuration.enableSeekSwipe)
          Positioned(
            left: swipeAreaWidth, // Start after left gesture zone
            right: swipeAreaWidth, // End before right gesture zone
            bottom: 20, // Small strip near bottom
            height: 60, // Small height to not interfere with buttons
            child: GestureDetector(
              behavior: HitTestBehavior.translucent, // Let taps pass through while catching drags
              onHorizontalDragStart: !widget.controlsVisible ? _onHorizontalDragStart : null,
              onHorizontalDragUpdate: !widget.controlsVisible
                  ? (details) => _onHorizontalDragUpdate(details, size.width)
                  : null,
              onHorizontalDragEnd: !widget.controlsVisible ? _onHorizontalDragEnd : null,
              onTap: _onSwipeAreaTap,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Feedback overlay (always on top)
        if (_isGestureActive && _currentGesture != null) _buildFeedbackOverlay(),
      ],
    );
  }

  Widget _buildFeedbackOverlay() {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final onSurfaceColor = theme.colorScheme.onSurface;
    double? positionedLeft =
        _currentGesture == GestureFeedbackType.volume || _currentGesture == GestureFeedbackType.seekBackward
        ? 20
        : null;
    double? positionedRight =
        _currentGesture == GestureFeedbackType.brightness || _currentGesture == GestureFeedbackType.seekForward
        ? 20
        : null;

    return Positioned(
      left: positionedLeft,
      right: positionedRight,
      top: 60.0,
      bottom: 60.0,
      child: _buildFeedbackContent(primaryColor, onSurfaceColor),
    );
  }

  Widget _buildFeedbackContent(Color primaryColor, Color onSurfaceColor) {
    switch (_currentGesture!) {
      case GestureFeedbackType.volume:
        return _buildVolumeIndicator(primaryColor, onSurfaceColor);
      case GestureFeedbackType.brightness:
        return _buildBrightnessIndicator(primaryColor, onSurfaceColor);
      case GestureFeedbackType.seekForward:
      case GestureFeedbackType.seekBackward:
        return _buildSeekIndicator(primaryColor, onSurfaceColor);
    }
  }

  Widget _buildVolumeIndicator(Color primaryColor, Color textColor) {
    final percentage = (_gestureValue * 100).round();
    final isMuted = percentage == 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isMuted ? Icons.volume_off : Icons.volume_up, color: primaryColor, size: 26),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          width: 8,
          child: RotatedBox(
            quarterTurns: -1, // -1 = 90° counter-clockwise
            child: LinearProgressIndicator(
              value: _gestureValue,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              minHeight: 8,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$percentage%',
          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildBrightnessIndicator(Color primaryColor, Color textColor) {
    final percentage = (_gestureValue * 100).round();

    // Use more granular brightness icons
    IconData brightnessIcon;
    if (percentage < 20) {
      brightnessIcon = Icons.brightness_low;
    } else if (percentage < 70) {
      brightnessIcon = Icons.brightness_medium;
    } else {
      brightnessIcon = Icons.brightness_high;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(brightnessIcon, color: primaryColor, size: 26),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          width: 8,
          child: RotatedBox(
            quarterTurns: -1, // -1 = 90° counter-clockwise
            child: LinearProgressIndicator(
              value: _gestureValue,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              minHeight: 8,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$percentage%',
          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSeekIndicator(Color primaryColor, Color textColor) {
    final seconds = _gestureValue.abs().round();
    final isForward = _currentGesture == GestureFeedbackType.seekForward;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isForward ? Icons.fast_forward : Icons.fast_rewind, color: primaryColor, size: 36),
        const SizedBox(width: 12),
        Text(
          '${isForward ? '+' : '-'}${seconds}s',
          style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
