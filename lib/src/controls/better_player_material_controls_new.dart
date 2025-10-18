import 'dart:async';
import 'package:better_player/src/configuration/better_player_controls_configuration.dart';
import 'package:better_player/src/controls/better_player_clickable_widget.dart';
import 'package:better_player/src/controls/better_player_controls_state.dart';
import 'package:better_player/src/controls/better_player_material_progress_bar.dart';
import 'package:better_player/src/controls/better_player_multiple_gesture_detector.dart';
import 'package:better_player/src/controls/better_player_progress_colors.dart';
import 'package:better_player/src/core/better_player_controller.dart';
import 'package:better_player/src/core/better_player_utils.dart';
import 'package:better_player/src/video_player/video_player.dart';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BetterPlayerMaterialControls extends StatefulWidget {
  ///Callback used to send information if player bar is hidden or not
  final Function(bool visbility) onControlsVisibilityChanged;

  ///Callback used to send information if player is in full screen or not
  final Function(bool isFullscreen) onFullScreenChanged;

  ///Controls config
  final BetterPlayerControlsConfiguration controlsConfiguration;

  const BetterPlayerMaterialControls({
    Key? key,
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
    required this.onFullScreenChanged,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _BetterPlayerMaterialControlsState();
  }
}

class _BetterPlayerMaterialControlsState
    extends BetterPlayerControlsState<BetterPlayerMaterialControls> {
  VideoPlayerValue? _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  bool _displayTapped = false;
  bool _wasLoading = false;
  bool _fastForward = false;
  bool _fastRewind = false;
  late int _fastForwardTime =
      betterPlayerControlsConfiguration.forwardSkipTimeInMilliseconds;
  late int _fastRewindTime =
      betterPlayerControlsConfiguration.backwardSkipTimeInMilliseconds;
  Duration? _newSkipPosition;
  Timer? _fastFwdRwdTimer;
  VideoPlayerController? _controller;
  BetterPlayerController? _betterPlayerController;
  StreamSubscription? _controlsVisibilityStreamSubscription;

  BetterPlayerControlsConfiguration get _controlsConfiguration =>
      widget.controlsConfiguration;

  @override
  VideoPlayerValue? get latestValue => _latestValue;

  @override
  BetterPlayerController? get betterPlayerController => _betterPlayerController;

  @override
  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration =>
      _controlsConfiguration;

  @override
  Widget build(BuildContext context) {
    return buildLTRDirectionality(_buildMainWidget());
  }

  ///Builds main widget of the controls.
  Widget _buildMainWidget() {
    _wasLoading = isLoading(_latestValue);
    if (_latestValue?.hasError == true) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(),
      );
    }
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.arrowUp): _UpIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): _DownIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): _LeftIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): _RightIntent(),
        LogicalKeySet(LogicalKeyboardKey.select): _SelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): _SelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): _BackIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): _BackIntent(),
      },
      child: Actions(
        actions: {
          _UpIntent: CallbackAction(onInvoke: (_) {
            if (!_betterPlayerController!.isVideoInitialized()!) {
              return KeyEventResult.ignored;
            }
            if (_betterPlayerController!.controlsEnabled) {
              if (controlsNotVisible) {
                onShowMoreClicked();
              } else {
                cancelAndRestartTimer();
              }
            } else {
              if (controlsNotVisible) {
                changePlayerControlsNotVisible(false);
              } else {
                cancelAndRestartTimer();
              }
            }
            return KeyEventResult.ignored;
          }),
          _DownIntent: CallbackAction(onInvoke: (_) {
            if (!_betterPlayerController!.isVideoInitialized()!) {
              return KeyEventResult.ignored;
            }
            if (controlsNotVisible) {
              changePlayerControlsNotVisible(false);
            } else {
              cancelAndRestartTimer();
            }
            return KeyEventResult.ignored;
          }),
          _LeftIntent: CallbackAction(onInvoke: (_) {
            if (!_betterPlayerController!.isVideoInitialized()! ||
                _betterPlayerController!.isLiveStream()) {
              return KeyEventResult.ignored;
            }
            if (_betterPlayerController!.controlsEnabled) {
              if (controlsNotVisible) {
                if (_fastForward) {
                  _fastForward = false;
                  _fastFwdRwdTimer?.cancel();
                }
                if (!_fastRewind) {
                  _fastRewind = true;
                  _startFwdRwdTimer();
                } else {
                  _fastRewindTime = (_fastRewindTime +
                      betterPlayerControlsConfiguration
                          .backwardSkipTimeInMilliseconds);
                  _restartFwdRwdTimer();
                }
                _newSkipPosition =
                    skipBack(enableTimer: false) ?? _newSkipPosition;
              } else {
                cancelAndRestartTimer();
              }
            } else {
              if (controlsNotVisible) {
                changePlayerControlsNotVisible(false);
              } else {
                cancelAndRestartTimer();
              }
            }
            return KeyEventResult.ignored;
          }),
          _RightIntent: CallbackAction(onInvoke: (_) {
            if (!_betterPlayerController!.isVideoInitialized()! ||
                _betterPlayerController!.isLiveStream()) {
              return KeyEventResult.ignored;
            }
            if (_betterPlayerController!.controlsEnabled) {
              if (controlsNotVisible) {
                if (_fastRewind) {
                  _fastRewind = false;
                  _fastFwdRwdTimer?.cancel();
                }
                if (!_fastForward) {
                  _fastForward = true;
                  _startFwdRwdTimer();
                } else {
                  _fastForwardTime = (_fastForwardTime +
                      betterPlayerControlsConfiguration
                          .forwardSkipTimeInMilliseconds);
                  _restartFwdRwdTimer();
                }
                _newSkipPosition =
                    skipForward(enableTimer: false) ?? _newSkipPosition;
              } else {
                cancelAndRestartTimer();
              }
            } else {
              if (controlsNotVisible) {
                changePlayerControlsNotVisible(false);
              } else {
                cancelAndRestartTimer();
              }
            }
            return KeyEventResult.ignored;
          }),
          _SelectIntent: CallbackAction(onInvoke: (_) {
            if (!_betterPlayerController!.isVideoInitialized()!) {
              return KeyEventResult.ignored;
            }
            if (controlsNotVisible) {
              changePlayerControlsNotVisible(false);
            }
            return KeyEventResult.ignored;
          }),
          _BackIntent: CallbackAction(onInvoke: (_) {
            if (!controlsNotVisible) {
              changePlayerControlsNotVisible(true);
            }
            return KeyEventResult.ignored;
          }),
        },
        child: GestureDetector(
          onTap: () {
            if (BetterPlayerMultipleGestureDetector.of(context) != null) {
              BetterPlayerMultipleGestureDetector.of(context)!.onTap?.call();
            }
            controlsNotVisible
                ? cancelAndRestartTimer()
                : changePlayerControlsNotVisible(true);
          },
          onDoubleTap: () {
            if (BetterPlayerMultipleGestureDetector.of(context) != null) {
              BetterPlayerMultipleGestureDetector.of(context)!
                  .onDoubleTap
                  ?.call();
            }
            cancelAndRestartTimer();
          },
          onLongPress: () {
            if (BetterPlayerMultipleGestureDetector.of(context) != null) {
              BetterPlayerMultipleGestureDetector.of(context)!
                  .onLongPress
                  ?.call();
            }
          },
          child: AbsorbPointer(
            absorbing: controlsNotVisible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_wasLoading)
                  Center(child: _buildLoadingWidget())
                else
                  _buildHitArea(),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(),
                ),
                Positioned(
                    bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
                _buildNextVideoWidget(),
              ],
            ),
          ),
        ),
      ),
    );
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
    _fastFwdRwdTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _controlsVisibilityStreamSubscription?.cancel();
  }

  @override
  void didChangeDependencies() {
    final _oldController = _betterPlayerController;
    _betterPlayerController = BetterPlayerController.of(context);
    _controller = _betterPlayerController!.videoPlayerController;
    _latestValue = _controller!.value;

    if (_oldController != _betterPlayerController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  Widget _buildErrorWidget() {
    final errorBuilder =
        _betterPlayerController!.betterPlayerConfiguration.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(
          context,
          _betterPlayerController!
              .videoPlayerController!.value.errorDescription);
    } else {
      final textStyle = TextStyle(color: _controlsConfiguration.textColor);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_rounded,
              color: _controlsConfiguration.iconsColor,
              size: 42,
            ),
            Text(
              _betterPlayerController!.translations.generalDefaultError,
              style: textStyle,
            ),
            if (_controlsConfiguration.enableRetry)
              TextButton(
                onPressed: () {
                  _betterPlayerController!.retryDataSource();
                },
                child: Text(
                  _betterPlayerController!.translations.generalRetry,
                  style: textStyle.copyWith(fontWeight: FontWeight.bold),
                ),
              )
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
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildHideUnhide(betterPlayerController!),
              SizedBox(
                width: _betterPlayerController!.isFullScreen ? 50 : 40,
              )
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
                    _buildBackButton(),
                    Expanded(
                      child: _buildTitleText(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildHideUnhide(betterPlayerController!),
                        if (_controlsConfiguration.enablePip)
                          _buildPipButtonWrapperWidget(
                              controlsNotVisible, _onPlayerHide)
                        else
                          const SizedBox(),
                        _buildMoreButton(),
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
          size: _betterPlayerController!.isFullScreen ? 26 : 20,
        ),
      ),
    );
  }

  Widget _buildTitleText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Visibility(
          visible: betterPlayerControlsConfiguration.title.isNotEmpty,
          child: Text(
            betterPlayerControlsConfiguration.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: _betterPlayerController!.isFullScreen ? 16 : 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Visibility(
          visible: betterPlayerControlsConfiguration.subtitle.isNotEmpty,
          child: Text(
            betterPlayerControlsConfiguration.subtitle,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: _betterPlayerController!.isFullScreen ? 14 : 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPipButton() {
    return BetterPlayerMaterialClickableWidget(
      onTap: () {
        betterPlayerController!.enablePictureInPicture(
            betterPlayerController!.betterPlayerGlobalKey!);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          betterPlayerControlsConfiguration.pipMenuIcon,
          color: betterPlayerControlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 26 : 20,
        ),
      ),
    );
  }

  Widget _buildPipButtonWrapperWidget(
      bool hideStuff, void Function() onPlayerHide) {
    return FutureBuilder<bool>(
      future: betterPlayerController!.isPictureInPictureSupported(),
      builder: (context, snapshot) {
        final bool isPipSupported = snapshot.data ?? false;
        if (isPipSupported &&
            _betterPlayerController!.betterPlayerGlobalKey != null) {
          return AnimatedOpacity(
            opacity: hideStuff ? 0.0 : 1.0,
            duration: betterPlayerControlsConfiguration.controlsHideTime,
            onEnd: onPlayerHide,
            child: Container(
              height: betterPlayerControlsConfiguration.controlBarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildPipButton(),
                ],
              ),
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
          size: _betterPlayerController!.isFullScreen ? 26 : 20,
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
        height: _controlsConfiguration.controlBarHeight + 20.0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              flex: 75,
              child: Row(
                children: [
                  if (_controlsConfiguration.enablePlayPause)
                    _buildPlayPause(_controller!)
                  else
                    const SizedBox(),
                  if (_betterPlayerController!.isLiveStream())
                    _buildLiveWidget()
                  else
                    _controlsConfiguration.enableProgressText
                        ? Expanded(child: _buildPosition())
                        : const SizedBox(),
                  const Spacer(),
                  if (_controlsConfiguration.enableMute)
                    _buildMuteButton(_controller)
                  else
                    const SizedBox(),
                  if (_controlsConfiguration.enableFullscreen)
                    _buildExpandButton()
                  else
                    const SizedBox(),
                ],
              ),
            ),
            if (_betterPlayerController!.isLiveStream())
              const SizedBox()
            else
              _controlsConfiguration.enableProgressBar
                  ? _buildProgressBar()
                  : const SizedBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveWidget() {
    return Text(
      _betterPlayerController!.translations.controlsLive,
      style: TextStyle(
          color: _controlsConfiguration.liveTextColor,
          fontWeight: FontWeight.bold),
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
                size: _betterPlayerController!.isFullScreen ? 26 : 20,
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
      child: Stack(
        alignment: AlignmentDirectional.center,
        children: [
          AnimatedOpacity(
            opacity: controlsNotVisible ? 0.0 : 1.0,
            duration: _controlsConfiguration.controlsHideTime,
            child: _buildMiddleRow(),
          ),
          Visibility(
            visible: _fastRewind && controlsNotVisible,
            child: _buildFastRewind(),
          ),
          Visibility(
            visible: _fastForward && controlsNotVisible,
            child: _buildFastForward(),
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleRow() {
    if (_betterPlayerController!.isVideoInitialized()! &&
        _newSkipPosition == null) {
      _newSkipPosition =
          _latestValue != null ? _latestValue!.position : Duration.zero;
    }
    return Container(
      color: _controlsConfiguration.controlBarColor,
      width: double.infinity,
      height: double.infinity,
      child: _betterPlayerController?.isLiveStream() == true
          ? const SizedBox()
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (_controlsConfiguration.enableSkips)
                  Expanded(child: _buildSkipButton())
                else
                  const SizedBox(),
                Expanded(child: _buildReplayButton(_controller!)),
                if (_controlsConfiguration.enableSkips)
                  Expanded(child: _buildForwardButton())
                else
                  const SizedBox(),
              ],
            ),
    );
  }

  Widget _buildFastRewind() {
    return Positioned(
      left: 0,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 100, maxWidth: 350),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(65),
          borderRadius: BorderRadius.horizontal(right: Radius.circular(80)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.fast_rewind_rounded,
              size: 60,
              color: _controlsConfiguration.iconsColor,
            ),
            Text(
                '-${(_fastRewindTime / 1000).toInt()}s (${BetterPlayerUtils.formatDuration(_newSkipPosition!)})',
                style: TextStyle(fontSize: 24))
          ],
        ),
      ),
    );
  }

  Widget _buildFastForward() {
    return Positioned(
      right: 0,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 100, maxWidth: 350),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(65),
          borderRadius: BorderRadius.horizontal(left: Radius.circular(80)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.fast_forward_rounded,
              size: 60,
              color: _controlsConfiguration.iconsColor,
            ),
            Text(
                '+${(_fastForwardTime / 1000).toInt()}s (${BetterPlayerUtils.formatDuration(_newSkipPosition!)})',
                style: TextStyle(fontSize: 24))
          ],
        ),
      ),
    );
  }

  Widget _buildHitAreaClickableButton(
      {Widget? icon, required void Function() onClicked, bool? isFocused}) {
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
              child: Stack(
                children: [icon!],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkipButton() {
    return Focus(
      child: Builder(builder: (context) {
        bool isFocused = Focus.of(context).hasFocus;
        return _buildHitAreaClickableButton(
          icon: Icon(
            _controlsConfiguration.skipBackIcon,
            size: betterPlayerController!.isFullScreen ? 30 : 24,
            color: _controlsConfiguration.iconsColor,
          ),
          onClicked: skipBack,
          isFocused: isFocused,
        );
      }),
    );
  }

  Widget _buildForwardButton() {
    return Focus(
      child: Builder(builder: (context) {
        bool isFocused = Focus.of(context).hasFocus;
        return _buildHitAreaClickableButton(
          icon: Icon(
            _controlsConfiguration.skipForwardIcon,
            size: betterPlayerController!.isFullScreen ? 30 : 24,
            color: _controlsConfiguration.iconsColor,
          ),
          onClicked: skipForward,
          isFocused: isFocused,
        );
      }),
    );
  }

  Widget _buildReplayButton(VideoPlayerController controller) {
    final bool isFinished = isVideoFinished(_latestValue);
    return Focus(
      child: Builder(builder: (context) {
        bool isFocused = Focus.of(context).hasFocus;
        return _buildHitAreaClickableButton(
          icon: isFinished
              ? Icon(
                  Icons.replay,
                  size: _betterPlayerController!.isFullScreen ? 50 : 42,
                  color: _controlsConfiguration.iconsColor,
                )
              : Icon(
                  controller.value.isPlaying
                      ? _controlsConfiguration.pauseIcon
                      : _controlsConfiguration.playIcon,
                  size: _betterPlayerController!.isFullScreen ? 50 : 42,
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
      }),
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
                margin: EdgeInsets.only(
                    bottom: _controlsConfiguration.controlBarHeight + 20,
                    right: 24),
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

  Widget _buildMuteButton(
    VideoPlayerController? controller,
  ) {
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
              size: _betterPlayerController!.isFullScreen ? 26 : 20,
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          controller.value.isPlaying
              ? _controlsConfiguration.pauseIcon
              : _controlsConfiguration.playIcon,
          color: _controlsConfiguration.iconsColor,
          size: _betterPlayerController!.isFullScreen ? 26 : 20,
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
            _betterPlayerController!.controlsEnabled
                ? Icons.lock_outline_rounded
                : Icons.lock_open_rounded,
            size: _betterPlayerController!.isFullScreen ? 26 : 20,
            color: betterPlayerControlsConfiguration.iconsColor,
          ),
        ));
  }

  Widget _buildPosition() {
    final position =
        _latestValue != null ? _latestValue!.position : Duration.zero;
    final duration = _latestValue != null && _latestValue!.duration != null
        ? _latestValue!.duration!
        : Duration.zero;
    final remaining = duration - position;
    String formattedTotalDuration = BetterPlayerUtils.formatDuration(duration);
    String formattedRemainingDuration =
        "-" + BetterPlayerUtils.formatDuration(remaining);

    return Padding(
      padding: _controlsConfiguration.enablePlayPause
          ? const EdgeInsets.only(right: 24)
          : const EdgeInsets.symmetric(horizontal: 22),
      child: RichText(
        text: TextSpan(
            text: BetterPlayerUtils.formatDuration(position),
            style: TextStyle(
              fontSize: _betterPlayerController!.isFullScreen ? 13.0 : 10.0,
              color: _controlsConfiguration.textColor,
              decoration: TextDecoration.none,
            ),
            children: <TextSpan>[
              TextSpan(
                text:
                    ' / ${_betterPlayerController!.betterPlayerControlsConfiguration.playerTimeMode == 1 ? formattedTotalDuration : formattedRemainingDuration}',
                style: TextStyle(
                  fontSize: _betterPlayerController!.isFullScreen ? 13.0 : 10.0,
                  color: _controlsConfiguration.textColor,
                  decoration: TextDecoration.none,
                ),
              )
            ]),
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

    if ((_controller!.value.isPlaying) ||
        _betterPlayerController!.betterPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }

    if (_controlsConfiguration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        changePlayerControlsNotVisible(false);
      });
    }

    _controlsVisibilityStreamSubscription =
        _betterPlayerController!.controlsVisibilityStream.listen((state) {
      changePlayerControlsNotVisible(!state);
      if (!controlsNotVisible) {
        cancelAndRestartTimer();
      }
    });
  }

  void _onExpandCollapse() {
    changePlayerControlsNotVisible(true);
    _betterPlayerController!.toggleFullScreen();
    _showAfterExpandCollapseTimer =
        Timer(_controlsConfiguration.controlsHideTime, () {
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
          ? {
              _betterPlayerController!.exitFullScreen(),
              _onFullScreenExit(false)
            }
          : {
              Navigator.pop(
                  context, _controlsConfiguration.onFullScreenChange ?? () {})
            };
    } else {
      _betterPlayerController!.isFullScreen
          ? {
              _betterPlayerController!.exitFullScreen(),
              _onFullScreenExit(false)
            }
          : Navigator.pop(context);
    }
  }

  void _onHideUnHide() {
    if (_betterPlayerController!.controlsEnabled) {
      changePlayerControlsNotVisible(false);
      _hideTimer?.cancel();
      _betterPlayerController!.setControlsEnabled(false);
    } else {
      cancelAndRestartTimer();
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

  void _startFwdRwdTimer() {
    _fastFwdRwdTimer = Timer(const Duration(seconds: 2), () {
      if (_fastForward) {
        _fastForward = false;
        _fastForwardTime =
            betterPlayerControlsConfiguration.forwardSkipTimeInMilliseconds;
      }
      if (_fastRewind) {
        _fastRewind = false;
        _fastRewindTime =
            betterPlayerControlsConfiguration.backwardSkipTimeInMilliseconds;
      }
    });
  }

  void _restartFwdRwdTimer() {
    _fastFwdRwdTimer?.cancel();
    _startFwdRwdTimer();
  }

  void _updateState() {
    if (mounted) {
      if (!controlsNotVisible ||
          isVideoFinished(_controller!.value) ||
          _wasLoading ||
          isLoading(_controller!.value)) {
        setState(() {
          _latestValue = _controller!.value;
          if (isVideoFinished(_latestValue) &&
              _betterPlayerController?.isLiveStream() == false) {
            changePlayerControlsNotVisible(false);
          }
        });
      }
    }
  }

  Widget _buildProgressBar() {
    return Expanded(
      flex: 40,
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
              backgroundColor:
                  _controlsConfiguration.progressBarBackgroundColor),
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
      return Container(
        color: _controlsConfiguration.controlBarColor,
        child: _controlsConfiguration.loadingWidget,
      );
    }

    return CircularProgressIndicator(
      valueColor:
          AlwaysStoppedAnimation<Color>(_controlsConfiguration.loadingColor),
    );
  }
}

// Intent classes
class _UpIntent extends Intent {}

class _DownIntent extends Intent {}

class _LeftIntent extends Intent {}

class _RightIntent extends Intent {}

class _SelectIntent extends Intent {}

class _BackIntent extends Intent {}
