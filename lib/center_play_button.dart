import 'package:flutter/material.dart';

class CenterPlayButton extends StatelessWidget {
    const CenterPlayButton({
        super.key,
        required this.backgroundColor,
        this.iconColor,
        required this.show,
        required this.isPlaying,
        required this.isFinished,
        this.onPressed,
    });

    final Color backgroundColor;
    final Color? iconColor;
    final bool show;
    final bool isPlaying;
    final bool isFinished;
    final VoidCallback? onPressed;

    @override
    Widget build(BuildContext context) {
        return AnimatedOpacity(
            opacity: show ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300), 
            child: ColoredBox(
            color: Colors.black26,
                child: Center(
                    child: UnconstrainedBox(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: backgroundColor,
                                shape: BoxShape.circle,
                            ),
                            child: IconButton(
                                iconSize: 32,
                                padding: const EdgeInsets.all(12.0),
                                icon: isFinished
                                    ? Icon(Icons.replay, color: iconColor)
                                    : AnimatedPlayPause(
                                        color: iconColor,
                                        playing: isPlaying,
                                    ),
                                onPressed: onPressed,
                            ),
                        ),
                    ),
                ),
            ),
        );
    }
}

class AnimatedPlayPause extends StatefulWidget {
    const AnimatedPlayPause({
        super.key,
        required this.playing,
        this.size,
        this.color,
    });

    final double? size;
    final bool playing;
    final Color? color;

    @override
    State<StatefulWidget> createState() => AnimatedPlayPauseState();
}

class AnimatedPlayPauseState extends State<AnimatedPlayPause> with SingleTickerProviderStateMixin {
    late final animationController = AnimationController(
        vsync: this,
        value: widget.playing ? 1 : 0,
        duration: const Duration(milliseconds: 400),
    );

    @override
    void didUpdateWidget(AnimatedPlayPause oldWidget) {
        super.didUpdateWidget(oldWidget);
        if (widget.playing != oldWidget.playing) {
            if (widget.playing) {
                animationController.forward();
            } else {
                animationController.reverse();
            }
        }
    }

    @override
    void dispose() {
        animationController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return Center(
            child: AnimatedIcon(
                color: widget.color,
                size: widget.size,
                icon: AnimatedIcons.play_pause,
                progress: animationController,
            ),
        );
    }
}

