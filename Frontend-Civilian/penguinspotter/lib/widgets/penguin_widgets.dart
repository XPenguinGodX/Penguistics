import 'package:flutter/material.dart';
import 'package:penguin/theme/penguin_theme.dart';

/// A small emperor penguin drawn with shapes, so the app needs no image assets.
class PenguinLogo extends StatelessWidget {
  const PenguinLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Penguistics logo',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _PenguinPainter()),
    );
  }
}

class _PenguinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 100x100 grid, then scaled to the requested size
    canvas.scale(size.width / 100, size.height / 100);
    Paint fill(Color color) => Paint()..color = color;

    canvas.drawOval(const Rect.fromLTRB(32, 88, 48, 99), fill(PenguinColors.orange));
    canvas.drawOval(const Rect.fromLTRB(52, 88, 68, 99), fill(PenguinColors.orange));
    canvas.drawOval(const Rect.fromLTRB(18, 4, 82, 94), fill(PenguinColors.black));
    // White rim so the black body still reads on the black Midnight theme
    canvas.drawOval(
      const Rect.fromLTRB(18, 4, 82, 94),
      Paint()
        ..color = PenguinColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawOval(const Rect.fromLTRB(30, 36, 70, 92), fill(PenguinColors.white));
    canvas.drawOval(const Rect.fromLTRB(29, 16, 71, 52), fill(PenguinColors.white));
    canvas.drawOval(const Rect.fromLTRB(21, 38, 33, 54), fill(PenguinColors.yellow));
    canvas.drawOval(const Rect.fromLTRB(67, 38, 79, 54), fill(PenguinColors.yellow));
    canvas.drawCircle(const Offset(42, 31), 4.5, fill(PenguinColors.black));
    canvas.drawCircle(const Offset(58, 31), 4.5, fill(PenguinColors.black));
    canvas.drawCircle(const Offset(43.5, 29.5), 1.5, fill(PenguinColors.white));
    canvas.drawCircle(const Offset(59.5, 29.5), 1.5, fill(PenguinColors.white));
    final beak = Path()
      ..moveTo(44, 38)
      ..lineTo(56, 38)
      ..lineTo(50, 48)
      ..close();
    canvas.drawPath(beak, fill(PenguinColors.orange));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Penguistics" with the second half in neck-patch yellow.
class PenguinWordmark extends StatelessWidget {
  const PenguinWordmark({super.key, this.fontSize = 26});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
        children: const [
          TextSpan(text: 'Pengu', style: TextStyle(color: PenguinColors.white)),
          TextSpan(text: 'istics', style: TextStyle(color: PenguinColors.yellow)),
        ],
      ),
    );
  }
}

/// Night-sky backdrop with a charcoal card, shared by the login and signup pages.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: PenguinColors.black,
      body: Stack(
        children: [
          // Soft "ice floes" drifting in the background
          const Positioned(top: -60, left: -40, child: _IceFloe(size: 220)),
          const Positioned(bottom: -80, right: -50, child: _IceFloe(size: 280)),
          const Positioned(top: 140, right: 30, child: _IceFloe(size: 70)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Material(
                    color: PenguinColors.charcoal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: PenguinColors.outline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          color: PenguinColors.black,
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                          child: const Column(
                            children: [
                              PenguinLogo(size: 72),
                              SizedBox(height: 10),
                              PenguinWordmark(),
                            ],
                          ),
                        ),
                        Container(height: 6, color: PenguinColors.yellow),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(title, style: text.headlineMedium),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: text.bodyLarge?.copyWith(
                                  color: PenguinColors.muted,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ...children,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IceFloe extends StatelessWidget {
  const _IceFloe({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: PenguinColors.blue.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}

enum PenguinTone { info, success, warning }

extension on PenguinTone {
  Color get background => switch (this) {
    PenguinTone.info => PenguinColors.charcoalHigh,
    PenguinTone.success => PenguinColors.yellow,
    PenguinTone.warning => PenguinColors.orange,
  };

  Color get foreground =>
      this == PenguinTone.info ? PenguinColors.white : PenguinColors.black;

  // Info keeps white text but gets a blue icon, so it doesn't look disabled
  Color get iconColor =>
      this == PenguinTone.info ? PenguinColors.blue : foreground;

  IconData get icon => switch (this) {
    PenguinTone.info => Icons.info_outline_rounded,
    PenguinTone.success => Icons.check_circle_rounded,
    PenguinTone.warning => Icons.error_outline_rounded,
  };
}

/// Replaces any visible snackbar with one in the penguin palette.
void showPenguinSnack(
  BuildContext context,
  String message, {
  PenguinTone tone = PenguinTone.info,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: tone.background,
        content: Row(
          children: [
            Icon(tone.icon, color: tone.iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: tone.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

/// An inline callout, used for report progress and results.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.tone = PenguinTone.info,
    this.busy = false,
  });

  final String message;
  final PenguinTone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: tone == PenguinTone.info
                        ? PenguinColors.yellow
                        : tone.foreground,
                  ),
                )
              : Icon(tone.icon, color: tone.iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: tone.foreground,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
