import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// A custom loading widget that shows an animated truck driving across a road.
/// Use this in place of [CircularProgressIndicator] for full-page loaders.
class TruckLoader extends StatefulWidget {
  /// Label shown below the animation. Defaults to "Loading…"
  final String label;

  /// Color of the truck icon and road accent. Defaults to [AppTheme.primaryColor].
  final Color color;

  /// Size of the overall container. The truck scales proportionally.
  final double size;

  const TruckLoader({
    super.key,
    this.label = 'Loading\u2026',
    this.color = AppTheme.primaryColor,
    this.size = 180,
  });

  @override
  State<TruckLoader> createState() => _TruckLoaderState();
}

class _TruckLoaderState extends State<TruckLoader>
    with TickerProviderStateMixin {
  late final AnimationController _driveController;
  late final AnimationController _bounceController;
  late final AnimationController _wheelController;
  late final AnimationController _exhaustController;

  late final Animation<double> _driveAnim;
  late final Animation<double> _bounceAnim;
  late final Animation<double> _wheelAnim;
  late final Animation<double> _exhaustAnim;

  @override
  void initState() {
    super.initState();

    // Truck drives left to right across the track
    _driveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _driveAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _driveController, curve: Curves.easeInOut),
    );

    // Subtle vertical bounce (road bumps)
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    _bounceAnim = Tween<double>(begin: 0, end: -3).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // Wheel rotation
    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat();

    _wheelAnim = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _wheelController, curve: Curves.linear),
    );

    // Exhaust puff fade
    _exhaustController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _exhaustAnim = Tween<double>(begin: 0.1, end: 0.7).animate(
      CurvedAnimation(parent: _exhaustController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _driveController.dispose();
    _bounceController.dispose();
    _wheelController.dispose();
    _exhaustController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double trackWidth = widget.size;
    final double truckSize = widget.size * 0.32;
    final Color color = widget.color;
    final Color trackColor = color.withOpacity(0.15);
    final Color dotColor = color.withOpacity(0.35);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: trackWidth,
          height: widget.size * 0.55,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Road track
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Dashed centre line
              Positioned(
                bottom: 13,
                left: 0,
                right: 0,
                child: _DashedLine(color: dotColor, width: trackWidth),
              ),

              // Moving truck
              AnimatedBuilder(
                animation: Listenable.merge([
                  _driveAnim,
                  _bounceAnim,
                  _wheelAnim,
                  _exhaustAnim,
                ]),
                builder: (context, _) {
                  final double xOffset =
                      _driveAnim.value * (trackWidth - truckSize);
                  final double yOffset = _bounceAnim.value;

                  return Positioned(
                    left: xOffset,
                    bottom: 10 + yOffset,
                    child: _TruckBody(
                      size: truckSize,
                      color: color,
                      wheelAngle: _wheelAnim.value,
                      exhaustOpacity: _exhaustAnim.value,
                    ),
                  );
                },
              ),

              // Dust cloud at reset point
              AnimatedBuilder(
                animation: _driveAnim,
                builder: (context, _) {
                  final opacity = _driveAnim.value > 0.92
                      ? (1.0 - _driveAnim.value) / 0.08
                      : 0.0;
                  return Positioned(
                    left: 0,
                    bottom: 14,
                    child: Opacity(
                      opacity: opacity,
                      child: Icon(Icons.cloud, color: dotColor, size: 18),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Label
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Truck body
// ---------------------------------------------------------------------------

class _TruckBody extends StatelessWidget {
  final double size;
  final Color color;
  final double wheelAngle;
  final double exhaustOpacity;

  const _TruckBody({
    required this.size,
    required this.color,
    required this.wheelAngle,
    required this.exhaustOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final double cabWidth = size * 0.38;
    final double trailerWidth = size * 0.62;
    final double bodyHeight = size * 0.52;
    final double wheelSize = size * 0.22;

    return SizedBox(
      width: size,
      height: size * 0.68,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Exhaust puff (left = back of truck since it moves right)
          Positioned(
            left: -10,
            top: 4,
            child: Opacity(
              opacity: exhaustOpacity,
              child: Column(
                children: [
                  _ExhaustPuff(color: color, size: 8),
                  const SizedBox(height: 2),
                  _ExhaustPuff(color: color, size: 6),
                ],
              ),
            ),
          ),

          // Trailer
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: trailerWidth,
              height: bodyHeight,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                border: Border.all(color: color, width: 1.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.local_shipping,
                  color: color.withOpacity(0.4),
                  size: trailerWidth * 0.4,
                ),
              ),
            ),
          ),

          // Cab
          Positioned(
            left: trailerWidth - 1,
            top: bodyHeight * 0.15,
            child: Container(
              width: cabWidth,
              height: bodyHeight * 0.85,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: cabWidth * 0.1,
                    top: bodyHeight * 0.08,
                  ),
                  child: Container(
                    width: cabWidth * 0.55,
                    height: bodyHeight * 0.35,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Rear wheel (trailer)
          Positioned(
            left: trailerWidth * 0.2,
            bottom: 0,
            child: _AnimatedWheel(
              size: wheelSize,
              angle: wheelAngle,
              color: color,
            ),
          ),

          // Middle wheel
          Positioned(
            left: trailerWidth * 0.72,
            bottom: 0,
            child: _AnimatedWheel(
              size: wheelSize,
              angle: wheelAngle,
              color: color,
            ),
          ),

          // Front wheel (cab)
          Positioned(
            left: trailerWidth + cabWidth * 0.45,
            bottom: 0,
            child: _AnimatedWheel(
              size: wheelSize,
              angle: wheelAngle,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedWheel extends StatelessWidget {
  final double size;
  final double angle;
  final Color color;

  const _AnimatedWheel({
    required this.size,
    required this.angle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.12),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExhaustPuff extends StatelessWidget {
  final Color color;
  final double size;
  const _ExhaustPuff({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed line painter
// ---------------------------------------------------------------------------

class _DashedLine extends StatelessWidget {
  final Color color;
  final double width;
  const _DashedLine({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, 2),
      painter: _DashedLinePainter(color: color),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    double x = 0;
    const dashWidth = 8.0;
    const gap = 6.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Convenience wrapper
// ---------------------------------------------------------------------------

/// Drop-in replacement for `Center(child: CircularProgressIndicator(...))`.
class TruckLoaderCenter extends StatelessWidget {
  final String label;
  final Color color;

  const TruckLoaderCenter({
    super.key,
    this.label = 'Loading\u2026',
    this.color = AppTheme.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TruckLoader(label: label, color: color),
    );
  }
}
