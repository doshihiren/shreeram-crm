import 'package:flutter/material.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = 40,
    this.showWordmark = true,
    this.wordmarkColor,
    this.compact = false,
  });

  final double height;
  final bool showWordmark;
  final Color? wordmarkColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/brand/logo-shreeram.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.apartment_rounded,
        size: height,
        color: wordmarkColor ?? AppTheme.brandGreenDark,
      ),
    );

    if (!showWordmark) return logo;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(width: compact ? 8 : 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ShreeRam',
                style: TextStyle(
                  color: wordmarkColor ?? AppTheme.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 16 : 20,
                  height: 1.1,
                ),
              ),
              Text(
                'Groups CRM',
                style: TextStyle(
                  color: (wordmarkColor ?? AppTheme.ink).withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 10 : 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
