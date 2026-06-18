import 'package:flutter/material.dart';

import '../theme/theme.dart';

class LifeHelmButton extends StatelessWidget {
  const LifeHelmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.variant = LifeHelmButtonVariant.primary,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final LifeHelmButtonVariant variant;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: fullWidth ? double.infinity : null,
        height: 52,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: LifeHelmColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
          ),
        ),
      );
    }

    final style = switch (variant) {
      LifeHelmButtonVariant.primary => ElevatedButton.styleFrom(
          backgroundColor: LifeHelmColors.primary,
          foregroundColor: Colors.white,
        ),
      LifeHelmButtonVariant.accent => ElevatedButton.styleFrom(
          backgroundColor: LifeHelmColors.accent,
          foregroundColor: LifeHelmColors.textOnAccent,
        ),
      LifeHelmButtonVariant.danger => ElevatedButton.styleFrom(
          backgroundColor: LifeHelmColors.danger,
          foregroundColor: Colors.white,
        ),
      LifeHelmButtonVariant.outline => ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: LifeHelmColors.primary,
          elevation: 0,
          side: const BorderSide(color: LifeHelmColors.primary),
        ),
    };

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: style.copyWith(
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          textStyle: const MaterialStatePropertyAll(
            TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
        label: Text(label),
      ),
    );
  }
}

enum LifeHelmButtonVariant { primary, accent, danger, outline }
