// lib/animations/coin_emission_animation.dart
import 'dart:math';
import 'package:flutter/material.dart';
///import 'package:flutter_windowmanager/flutter_windowmanager.dart';

class CoinEmissionAnimation extends StatefulWidget {
  final int coinCount;
  final Duration duration;
  final Widget child;
  final bool isActive;

  const CoinEmissionAnimation({
    super.key,
    required this.coinCount,
    required this.child,
    required this.isActive,
    this.duration = const Duration(seconds: 2),
  });

  @override
  _CoinEmissionAnimationState createState() => _CoinEmissionAnimationState();
}

class _CoinEmissionAnimationState extends State<CoinEmissionAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Animation<double>> _animations = [];
  final List<Offset> _positions = [];

  @override
  void initState() {
    super.initState();
    ///FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    _initializeAnimation();
  }

  void _initializeAnimation() {
    _controller = AnimationController(duration: widget.duration, vsync: this);

    for (int i = 0; i < widget.coinCount; i++) {
      final animation = CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      );
      _animations.add(animation);

      _positions.add(
        Offset(
          (Random().nextDouble() * 60) - 30,
          (Random().nextDouble() * -80) - 20,
        ),
      );
    }

    if (widget.isActive) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(CoinEmissionAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward(from: 0);
      } else {
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return widget.child;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,

        ...List.generate(widget.coinCount, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              final animationValue = _animations[index].value;

              return Positioned(
                right: _positions[index].dx,
                bottom: _positions[index].dy * animationValue,
                child: Opacity(
                  opacity: 1 - animationValue,
                  child: Transform.scale(
                    scale: 0.5 + (animationValue * 0.5),
                    child: Text(
                      '🪙',
                      style: TextStyle(
                        fontSize: 16,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}
