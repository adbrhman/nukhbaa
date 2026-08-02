library;

import 'package:flutter/material.dart';
import '../design/app_motion.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
  }) : _circle = false,
       _size = null;

  const AppSkeleton.circle({super.key, required double size})
    : _circle = true,
      _size = size,
      width = size,
      height = size,
      borderRadius = null;

  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final bool _circle;
  final double? _size;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;

    final BorderRadius br = widget._circle
        ? BorderRadius.circular(widget._size! / 2)
        : (widget.borderRadius ?? BorderRadius.circular(6));

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: LinearGradient(
              begin: Alignment(-1 - t * 2, 0),
              end: Alignment(1 - t * 2, 0),
              colors: [
                tokens.skeletonBase,
                tokens.skeletonHighlight,
                tokens.skeletonBase,
              ],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

class AppSkeletonListTile extends StatelessWidget {
  const AppSkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const AppSkeleton.circle(size: 44),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AppSkeleton(height: 14, width: 160),
                SizedBox(height: AppSpacing.sm),
                AppSkeleton(height: 12, width: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
