import 'dart:async';
import 'package:better_player_plus/src/configuration/better_player_controls_configuration.dart';
import 'package:better_player_plus/src/controls/better_player_clickable_widget.dart';
import 'package:better_player_plus/src/controls/better_player_controls_state.dart';
import 'package:better_player_plus/src/controls/better_player_gesture_controls.dart';
import 'package:better_player_plus/src/controls/better_player_material_progress_bar.dart';
import 'package:better_player_plus/src/controls/better_player_multiple_gesture_detector.dart';
import 'package:better_player_plus/src/controls/better_player_progress_colors.dart';
import 'package:better_player_plus/src/core/better_player_brightness_manager.dart';
import 'package:better_player_plus/src/core/better_player_controller.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';

// Flutter imports:
import 'package:flutter/material.dart';

class BetterPlayerMaterialControls extends StatefulWidget {
  ///Callback used to send information if player bar is hidden or not
  final Function(bool visbility) onControlsVisibilityChanged;

  ///Callback used to send information if player is in full screen or not
  final Function(bool isFullscreen) onFullScreenChanged;

  ///Controls config
  final BetterPlayerControlsConfiguration controlsConfiguration;

  const BetterPlayerMaterialControls({
    super.key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
    required this.onFullScreenChanged,
  });

  @override
  State<StatefulWidget> createState() {
    return _BetterPlayerMaterialControlsState();
  }
}

class _BetterPlayerMaterialControlsState extends BetterPlayerControlsState<BetterPlayerMaterialControls> {
  VideoPlayerValue? _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  bool _displayTapped = false;
  bool _wasLoading = false;
  int _playerTimeMode = 1;
  VideoPlayerController? _controller;
  BetterPlayerController? _betterPlayerController;
  StreamSubscription? _controlsVisibilityStreamSubscription;

  // Gesture control state
  double _currentBrightness = 0.5;
  bool _brightnessInitialized = false;

  BetterPlayerControlsConfiguration get _controlsConfiguration => widget.controlsConfiguration;

  @override
  VideoPlayerValue? get latestValue => _latestValue;

  @override
  BetterPlayerController? get betterPlayerController => _betterPlayerController;

  @override
  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration => _controlsConfiguration;

  @override
  Widget build(BuildContext context) {
    return buildLTRDirectionality(_buildMainWidget());
  }

  /// Initialize brightness on first build
  Future<void> _initializeBrightness() async {
    if (!_brightnessInitialized) {
      try {
        _currentBrightness = await BetterPlayerBrightnessManager.getBrightness();
        _brightnessInitialized = true;
      } catch (e) {
        BetterPlayerUtils.log('Failed to initialize brightness: $e');
      }
    }
  }

  /// Handle volume change from gesture
  void _onVolumeChanged(double volume) {
    _betterPlayerController?.setVolume(volume);
    setState(() {
      _latestVolume = volume;
    });
  }

  /// Handle brightness change from gesture
  void _onBrightnessChanged(double brightness) {
    setState(() {
      _currentBrightness = brightness;
    });
    BetterPlayerBrightnessManager.setBrightness(brightness);
  }

  /// Handle seek from gesture
  void _onSeek(Duration seekDuration) async {
    final currentPosition = await _controller?.position;
    if (currentPosition != null) {
      final newPosition = currentPosition + seekDuration;
      _betterPlayerController?.seekTo(newPosition);
    }
  }

  ///Builds main widget of the controls.
  Widget _buildMainWidget() {
    _wasLoading = isLoading(_latestValue);
    if (_latestValue?.hasError == true) {
      return Container(color: Colors.black, child: _buildErrorWidget());
    }

    // Initialize brightness on first build
    if (!_brightnessInitialized) {
      _initializeBrightness();
    }

    final gestureConfig = _controlsConfiguration.gestureConfiguration;
    final bool anyGestureEnabled =
        gestureConfig.enableVolumeSwipe ||
        gestureConfig.enableBrightnessSwipe ||
        gestureConfig.enableSeekSwipe ||
        gestureConfig.enableDoubleTapSeek;

    BetterPlayerUtils.log('🎯 BetterPlayer: anyGestureEnabled=$anyGestureEnabled, config=$gestureConfig');

    Widget mainContent = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (BetterPlayerMultipleGestureDetector.of(context) != null) {
          BetterPlayerMultipleGestureDetector.of(context)!.onTap?.call();
        }
        controlsNotVisible ? cancelAndRestartTimer() : changePlayerControlsNotVisible(true);
      },
      onDoubleTap: () {
        if (BetterPlayerMultipleGestureDetector.of(context) != null) {
          BetterPlayerMultipleGestureDetector.of(context)!.onDoubleTap?.call();
        }
        cancelAndRestartTimer();
      },
      onLongPress: () {
        if (BetterPlayerMultipleGestureDetector.of(context) != null) {
          BetterPlayerMultipleGestureDetector.of(context)!.onLongPress?.call();
        }
      },
      child: AbsorbPointer(
        absorbing: controlsNotVisible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_wasLoading) Center(child: _buildLoadingWidget()) else _buildHitArea(),
            Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
            _buildNextVideoWidget(),
          ],
        ),
      ),
    );

    // Wrap with gesture handler if any gesture is enabled
    // The gesture handler is outside AbsorbPointer so it can receive events even when controls are hidden
    if (anyGestureEnabled && _betterPlayerController!.isFullScreen) {
      BetterPlayerUtils.log('🎯 BetterPlayer: Wrapping with GestureHandler now!');
      mainContent = BetterPlayerGestureHandler(
        configuration: gestureConfig,
        currentVolume: _latestVolume ?? _latestValue?.volume ?? 0.5,
        currentBrightness: _currentBrightness,
        controlsVisible: !controlsNotVisible, // Pass controls visibility state
        onVolumeChanged: _onVolumeChanged,
        onBrightnessChanged: _onBrightnessChanged,
        onSeek: _onSeek,
        onSwipeAreaTap: () {
          changePlayerControlsNotVisible(!controlsNotVisible);
        },
        child: mainContent,
      );
      BetterPlayerUtils.log('🎯 BetterPlayer: GestureHandler wrapped!');
    } else {
      BetterPlayerUtils.log('🎯 BetterPlayer: NOT wrapping with GestureHandler - gestures disabled');
    }

    return mainContent;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    _controller?.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _betterPlayerController;
    _betterPlayerController = BetterPlayerController.of(context);
    _controller = _betterPlayerController!.videoPlayerController;
    _latestValue = _controller!.value;
    _playerTimeMode = _betterPlayerController!.betterPlayerControlsConfiguration.playerTimeMode ?? 1;

    if (oldController != _betterPlayerController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _buildErrorWidget() {
    final errorBuilder = _betterPlayerController!.betterPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(context, _betterPlayerController!.videoPlayerController!.value.errorDescription);
    } else {
      final textStyle = TextStyle(color: _controlsConfiguration.textColor);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_rounded, color: _controlsConfiguration.iconsColor, size: 42),
            Text(_betterPlayerController!.translations.generalDefaultError, style: textStyle),
            if (_controlsConfiguration.enableRetry)
              TextButton(
                onPressed: () {
                  _betterPlayerController!.retryDataSource();
                },
                child: Text(
                  _betterPlayerController!.translations.generalRetry,
                  style: textStyle.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      );
    }
  }

  Widget _buildTopBar() {
    if (!betterPlayerController!.controlsEnabled) {
      return AnimatedOpacity(
        opacity: controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        onEnd: _onPlayerHide,
        child: Container(
          height: _controlsConfiguration.controlBarHeight,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(width: _betterPlayerController!.isFullScreen ? 50 : 40),
              _buildHideUnhide(betterPlayerController!),
            ],
          ),
        ),
      );
    }

    return Container(
      child: (_controlsConfiguration.enableOverflowMenu)
          ? AnimatedOpacity(
              opacity: controlsNotVisible ? 0.0 : 1.0,
              duration: _controlsConfiguration.controlsHideTime,
              onEnd: _onPlayerHide,
              child: Container(
                height: _controlsConfiguration.controlBarHeight,
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [_buildBackButton(), _buildHideUnhide(betterPlayerController!)],
                    ),
                    Expanded(child: _buildTitleText()),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_controlsConfiguration.enableResize) _buildResizeButton() else const SizedBox(),
                        if (_controlsConfiguration.enablePip)
                          _buildPipButtonWrapperWidget(controlsNotVisible, _onPlayerHide)
                        else
                          const SizedBox(),
                        if (_controlsConfiguration.enableCast) _buildCastButton() else const SizedBox(),
                        _buildMoreButton(),
                        if (_controlsConfiguration.enableServer) _buildServerButton() else const SizedBox(),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox(),
    );
  }

  Widget _buildBackButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: _onBackClicked,
      child: Container(
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          Icons.arrow_back_ios_rounded,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildResizeButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: _onResizeClicked,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          betterPlayerControlsConfiguration.resizeIcon,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildCastButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        if (_controlsConfiguration.onCastTap != null) {
          _controlsConfiguration.onCastTap!();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          betterPlayerControlsConfiguration.castIcon,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildServerButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        if (_controlsConfiguration.onServerTap != null) {
          _controlsConfiguration.onServerTap!();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          betterPlayerControlsConfiguration.serverIcon,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildTitleText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (betterPlayerControlsConfiguration.title != null) ...[
          Text(
            betterPlayerControlsConfiguration.title!,
            style: TextStyle(color: Colors.white, fontSize: _betterPlayerController!.isFullScreen ? 16 : 14),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (betterPlayerControlsConfiguration.subtitle != null) ...[
          Text(
            betterPlayerControlsConfiguration.subtitle!,
            style: TextStyle(color: Colors.grey[500], fontSize: _betterPlayerController!.isFullScreen ? 14 : 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildPipButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        betterPlayerController!.enablePictureInPicture(betterPlayerController!.betterPlayerGlobalKey!);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          betterPlayerControlsConfiguration.pipMenuIcon,
          color: betterPlayerControlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildPipButtonWrapperWidget(bool hideStuff, void Function() onPlayerHide) {
    return FutureBuilder<bool>(
      future: betterPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final bool isPipSupported = snapshot.data ?? false;
        if (isPipSupported && _betterPlayerController!.betterPlayerGlobalKey != null) {
          return AnimatedOpacity(
            opacity: hideStuff ? 0.0 : 1.0,
            duration: betterPlayerControlsConfiguration.controlsHideTime,
            onEnd: onPlayerHide,
            child: Container(
              height: betterPlayerControlsConfiguration.controlBarHeight,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [_buildPipButton()]),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  Widget _buildMoreButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        onShowMoreClicked();
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          _controlsConfiguration.overflowMenuIcon,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (!betterPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    return AnimatedOpacity(
      opacity: controlsNotVisible ? 0.0 : 1.0,
      duration: _controlsConfiguration.controlsHideTime,
      onEnd: _onPlayerHide,
      child: Container(
        // tweak this to change the height of the progress bar together with the bottom part
        height: _betterPlayerController!.isFullScreen
            ? _controlsConfiguration.controlBarHeight + 30.0
            : _controlsConfiguration.controlBarHeight + 15.0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            if (_betterPlayerController!.isLiveStream())
              const SizedBox()
            else
              _controlsConfiguration.enableProgressBar ? _buildProgressBar() : const SizedBox(),
            Expanded(
              flex: 70,
              child: Row(
                children: [
                  if (_controlsConfiguration.enablePlayPause) _buildPlayPause(_controller!) else const SizedBox(),
                  if (_betterPlayerController!.isLiveStream())
                    _buildLiveWidget()
                  else
                    _controlsConfiguration.enableProgressText && !_betterPlayerController!.isFullScreen
                        ? Expanded(child: _buildPosition())
                        : const SizedBox(),
                  const Spacer(),
                  if (_controlsConfiguration.enableMute) _buildMuteButton(_controller) else const SizedBox(),
                  if (_controlsConfiguration.enableEpisodeSelection)
                    _buildEpisodeSelectionButton()
                  else
                    const SizedBox(),
                  if (_controlsConfiguration.enableMovieRecommendations)
                    _buildMovieRecommendationsButton()
                  else
                    const SizedBox(),
                  if (_controlsConfiguration.enableFullscreen) _buildExpandButton() else const SizedBox(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveWidget() {
    return Text(
      _betterPlayerController!.translations.controlsLive,
      style: TextStyle(color: _controlsConfiguration.liveTextColor, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildExpandButton() {
    return Padding(
      padding: EdgeInsets.only(right: 12.0),
      child: BetterPlayerMaterialClickableWidget(
        onTap: _onExpandCollapse,
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Icon(
                _betterPlayerController!.isFullScreen
                    ? _controlsConfiguration.fullscreenDisableIcon
                    : _controlsConfiguration.fullscreenEnableIcon,
                color: _controlsConfiguration.iconsColor,
                size: _betterPlayerController!.isFullScreen ? 30 : 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeSelectionButton() {
    return Padding(
      padding: EdgeInsets.only(right: 8.0),
      child: BetterPlayerMaterialClickableWidget(
        onTap: () {
          if (_controlsConfiguration.onEpisodeListTap != null) {
            _controlsConfiguration.onEpisodeListTap!();
          }
        },
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Icon(
                Icons.list_rounded,
                color: _controlsConfiguration.iconsColor,
                size: _betterPlayerController!.isFullScreen ? 30 : 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMovieRecommendationsButton() {
    return Padding(
      padding: EdgeInsets.only(right: 8.0),
      child: BetterPlayerMaterialClickableWidget(
        onTap: () {
          if (_controlsConfiguration.onMovieRecommendationsTap != null) {
            _controlsConfiguration.onMovieRecommendationsTap!();
          }
        },
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Icon(
                Icons.movie_filter_rounded,
                color: _controlsConfiguration.iconsColor,
                size: _betterPlayerController!.isFullScreen ? 30 : 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    if (!betterPlayerController!.controlsEnabled) {
      return const SizedBox();
    }
    return Container(
      child: Center(
        child: AnimatedOpacity(
          opacity: controlsNotVisible ? 0.0 : 1.0,
          duration: _controlsConfiguration.controlsHideTime,
          child: _buildMiddleRow(),
        ),
      ),
    );
  }

  Widget _buildMiddleRow() {
    return Container(
      color: _controlsConfiguration.controlBarColor,
      width: double.infinity,
      height: double.infinity,
      child: _betterPlayerController?.isLiveStream() == true
          ? const SizedBox()
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_controlsConfiguration.enableSkips) Expanded(child: _buildSkipButton()) else const SizedBox(),
                Expanded(child: _buildReplayButton(_controller!)),
                if (_controlsConfiguration.enableSkips) Expanded(child: _buildForwardButton()) else const SizedBox(),
              ],
            ),
    );
  }

  Widget _buildHitAreaClickableButton({Widget? icon, required void Function() onClicked, bool? isFocused}) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 80.0, maxWidth: 80.0),
      child: Align(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(200),
            border: (isFocused != null && isFocused)
                ? Border.all(color: _controlsConfiguration.iconsColor, width: 2)
                : null,
          ),
          child: BetterPlayerMaterialClickableWidget(
            onTap: onClicked,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(children: [icon!]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkipButton() {
    return Focus(
      child: Builder(
        builder: (context) {
          bool isFocused = Focus.of(context).hasFocus;
          return _buildHitAreaClickableButton(
            icon: Icon(
              _controlsConfiguration.skipBackIcon,
              size: betterPlayerController!.isFullScreen ? 46 : 34,
              color: _controlsConfiguration.iconsColor,
            ),
            onClicked: skipBack,
            isFocused: isFocused,
          );
        },
      ),
    );
  }

  Widget _buildForwardButton() {
    return Focus(
      child: Builder(
        builder: (context) {
          bool isFocused = Focus.of(context).hasFocus;
          return _buildHitAreaClickableButton(
            icon: Icon(
              _controlsConfiguration.skipForwardIcon,
              size: betterPlayerController!.isFullScreen ? 46 : 34,
              color: _controlsConfiguration.iconsColor,
            ),
            onClicked: skipForward,
            isFocused: isFocused,
          );
        },
      ),
    );
  }

  Widget _buildReplayButton(VideoPlayerController controller) {
    final bool isFinished = isVideoFinished(_latestValue);
    return Focus(
      child: Builder(
        builder: (context) {
          bool isFocused = Focus.of(context).hasFocus;
          return _buildHitAreaClickableButton(
            icon: isFinished
                ? Icon(
                    Icons.replay,
                    size: _betterPlayerController!.isFullScreen ? 60 : 48,
                    color: _controlsConfiguration.iconsColor,
                  )
                : Icon(
                    controller.value.isPlaying ? _controlsConfiguration.pauseIcon : _controlsConfiguration.playIcon,
                    size: _betterPlayerController!.isFullScreen ? 60 : 48,
                    color: _controlsConfiguration.iconsColor,
                  ),
            onClicked: () {
              if (isFinished) {
                if (_latestValue != null && _latestValue!.isPlaying) {
                  if (_displayTapped) {
                    changePlayerControlsNotVisible(true);
                  } else {
                    cancelAndRestartTimer();
                  }
                } else {
                  _onPlayPause();
                  changePlayerControlsNotVisible(true);
                }
              } else {
                _onPlayPause();
              }
            },
            isFocused: isFocused,
          );
        },
      ),
    );
  }

  Widget _buildNextVideoWidget() {
    return StreamBuilder<int?>(
      stream: _betterPlayerController!.nextVideoTimeStream,
      builder: (context, snapshot) {
        final time = snapshot.data;
        if (time != null && time > 0) {
          return BetterPlayerMaterialClickableWidget(
            onTap: () {
              _betterPlayerController!.playNextVideo();
            },
            child: Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: EdgeInsets.only(bottom: _controlsConfiguration.controlBarHeight + 20, right: 24),
                decoration: BoxDecoration(
                  color: _controlsConfiguration.controlBarColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "${_betterPlayerController!.translations.controlsNextVideoIn} $time...",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  Widget _buildMuteButton(VideoPlayerController? controller) {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        cancelAndRestartTimer();
        if (_latestValue!.volume == 0) {
          _betterPlayerController!.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller!.value.volume;
          _betterPlayerController!.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: controlsNotVisible ? 0.0 : 1.0,
        duration: _controlsConfiguration.controlsHideTime,
        child: ClipRect(
          child: Container(
            height: _controlsConfiguration.controlBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              (_latestValue != null && _latestValue!.volume > 0)
                  ? _controlsConfiguration.muteIcon
                  : _controlsConfiguration.unMuteIcon,
              color: _controlsConfiguration.iconsColor,
              size: _betterPlayerController!.isFullScreen ? 30 : 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPause(VideoPlayerController controller) {
    return BetterPlayerMaterialClickableWidget(
      key: const Key("better_player_material_controls_play_pause_button"),
      onTap: _onPlayPause,
      child: Container(
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          controller.value.isPlaying ? _controlsConfiguration.pauseIcon : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
        ),
      ),
    );
  }

  Widget _buildHideUnhide(BetterPlayerController controller) {
    return BetterPlayerMaterialClickableWidget(
      onTap: _onHideUnHide,
      child: Container(
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          _betterPlayerController!.controlsEnabled ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
          size: _betterPlayerController!.isFullScreen ? 30 : 22,
          color: betterPlayerControlsConfiguration.iconsColor,
        ),
      ),
    );
  }

  Widget _buildPosition() {
    final position = _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null ? _latestValue!.duration! : Duration.zero;
    final remaining = duration - position;
    String formattedTotalDuration = BetterPlayerUtils.formatDuration(duration);
    String formattedRemainingDuration = "-${BetterPlayerUtils.formatDuration(remaining)}";

    return Padding(
      padding: _controlsConfiguration.enablePlayPause
          ? const EdgeInsets.only(right: 24)
          : const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Text(
            '${BetterPlayerUtils.formatDuration(position)} / ',
            style: TextStyle(fontSize: 11.0, color: _controlsConfiguration.textColor, decoration: TextDecoration.none),
          ),
          GestureDetector(
            onTap: () {
              if (_playerTimeMode == 1) {
                _playerTimeMode = 2;
              } else {
                _playerTimeMode = 1;
              }
            },
            child: Text(
              _playerTimeMode == 1 ? formattedTotalDuration : formattedRemainingDuration,
              style: TextStyle(
                fontSize: 11.0,
                color: _controlsConfiguration.textColor,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    changePlayerControlsNotVisible(false);
    _displayTapped = true;
  }

  Future<void> _initialize() async {
    _controller!.addListener(_updateState);

    _updateState();

    if ((_controller!.value.isPlaying) || _betterPlayerController!.betterPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }

    if (_controlsConfiguration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        changePlayerControlsNotVisible(false);
      });
    }

    _controlsVisibilityStreamSubscription = _betterPlayerController!.controlsVisibilityStream.listen((state) {
      changePlayerControlsNotVisible(!state);
      if (!controlsNotVisible) {
        cancelAndRestartTimer();
      }
    });
  }

  void _onExpandCollapse() {
    changePlayerControlsNotVisible(true);
    _betterPlayerController!.toggleFullScreen();
    _showAfterExpandCollapseTimer = Timer(_controlsConfiguration.controlsHideTime, () {
      setState(() {
        cancelAndRestartTimer();
      });
    });
  }

  void _onPlayPause() {
    bool isFinished = false;

    if (_latestValue?.position != null && _latestValue?.duration != null) {
      isFinished = _latestValue!.position >= _latestValue!.duration!;
    }

    if (_controller!.value.isPlaying) {
      changePlayerControlsNotVisible(false);
      _hideTimer?.cancel();
      _betterPlayerController!.pause();
    } else {
      cancelAndRestartTimer();

      if (!_controller!.value.initialized) {
      } else {
        if (isFinished) {
          _betterPlayerController!.seekTo(const Duration());
        }
        _betterPlayerController!.play();
        _betterPlayerController!.cancelNextVideoTimer();
      }
    }
  }

  void _onBackClicked() {
    if (_betterPlayerController!.isVideoInitialized()!) {
      _betterPlayerController!.isFullScreen
          ? {_betterPlayerController!.exitFullScreen(), _onFullScreenExit(false)}
          : {Navigator.pop(context, _controlsConfiguration.onFullScreenChange ?? () {})};
    } else {
      _betterPlayerController!.isFullScreen
          ? {_betterPlayerController!.exitFullScreen(), _onFullScreenExit(false)}
          : Navigator.pop(context);
    }
  }

  void _onResizeClicked() {
    BoxFit fit = _betterPlayerController!.getFit();
    switch (fit) {
      case BoxFit.contain:
        _betterPlayerController!.setOverriddenFit(BoxFit.fill);
        if (_controlsConfiguration.onResizeTap != null) {
          _controlsConfiguration.onResizeTap!(BoxFit.fill);
        }
        break;
      case BoxFit.fill:
        _betterPlayerController!.setOverriddenFit(BoxFit.fitHeight);
        if (_controlsConfiguration.onResizeTap != null) {
          _controlsConfiguration.onResizeTap!(BoxFit.fitHeight);
        }
        break;
      case BoxFit.fitHeight:
        _betterPlayerController!.setOverriddenFit(BoxFit.fitWidth);
        if (_controlsConfiguration.onResizeTap != null) {
          _controlsConfiguration.onResizeTap!(BoxFit.fitWidth);
        }
        break;
      case BoxFit.fitWidth:
        _betterPlayerController!.setOverriddenFit(BoxFit.cover);
        if (_controlsConfiguration.onResizeTap != null) {
          _controlsConfiguration.onResizeTap!(BoxFit.cover);
        }
        break;
      case BoxFit.cover:
        _betterPlayerController!.setOverriddenFit(BoxFit.contain);
        if (_controlsConfiguration.onResizeTap != null) {
          _controlsConfiguration.onResizeTap!(BoxFit.contain);
        }
        break;
      default:
        _betterPlayerController!.setOverriddenFit(BoxFit.contain);
        if (_controlsConfiguration.onResizeTap != null) {
          _controlsConfiguration.onResizeTap!(BoxFit.contain);
        }
        break;
    }
  }

  void _onHideUnHide() {
    if (_betterPlayerController!.controlsEnabled) {
      _betterPlayerController!.setControlsEnabled(false);
    } else {
      _betterPlayerController!.setControlsEnabled(true);
    }
  }

  void _startHideTimer() {
    if (_betterPlayerController!.controlsAlwaysVisible) {
      return;
    }
    _hideTimer = Timer(betterPlayerControlsConfiguration.controlsHideDelay, () {
      changePlayerControlsNotVisible(true);
    });
  }

  void _updateState() {
    if (mounted) {
      if (!controlsNotVisible || isVideoFinished(_controller!.value) || _wasLoading || isLoading(_controller!.value)) {
        setState(() {
          _latestValue = _controller!.value;
          if (isVideoFinished(_latestValue) && _betterPlayerController?.isLiveStream() == false) {
            changePlayerControlsNotVisible(false);
          }
        });
      }
    }
  }

  Widget _buildProgressBar() {
    final position = _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null ? _latestValue!.duration! : Duration.zero;
    final remaining = duration - position;
    String formattedTotalDuration = BetterPlayerUtils.formatDuration(duration);
    String formattedRemainingDuration = "-${BetterPlayerUtils.formatDuration(remaining)}";

    return Expanded(
      flex: 35,
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (_betterPlayerController!.isFullScreen) ...[
              Text(
                BetterPlayerUtils.formatDuration(position),
                style: TextStyle(
                  fontSize: 14.0,
                  color: _controlsConfiguration.textColor,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(width: 12),
            ],
            Expanded(
              child: BetterPlayerMaterialVideoProgressBar(
                _controller,
                _betterPlayerController,
                onDragStart: () {
                  _hideTimer?.cancel();
                },
                onDragEnd: () {
                  _startHideTimer();
                },
                onTapDown: () {
                  cancelAndRestartTimer();
                },
                colors: BetterPlayerProgressColors(
                  playedColor: _controlsConfiguration.progressBarPlayedColor,
                  handleColor: _controlsConfiguration.progressBarHandleColor,
                  bufferedColor: _controlsConfiguration.progressBarBufferedColor,
                  backgroundColor: _controlsConfiguration.progressBarBackgroundColor,
                ),
                isFullScreen: _betterPlayerController!.isFullScreen,
              ),
            ),
            if (_betterPlayerController!.isFullScreen) ...[
              SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  if (_playerTimeMode == 1) {
                    _playerTimeMode = 2;
                  } else {
                    _playerTimeMode = 1;
                  }
                },
                child: Text(
                  _playerTimeMode == 1 ? formattedTotalDuration : formattedRemainingDuration,
                  style: TextStyle(
                    fontSize: 14.0,
                    color: _controlsConfiguration.textColor,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onPlayerHide() {
    _betterPlayerController!.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  void _onFullScreenExit(bool isFullscreen) {
    widget.onFullScreenChanged(isFullscreen);
  }

  Widget? _buildLoadingWidget() {
    if (_controlsConfiguration.loadingWidget != null) {
      return Container(color: _controlsConfiguration.controlBarColor, child: _controlsConfiguration.loadingWidget);
    }

    return CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_controlsConfiguration.loadingColor));
  }
}
