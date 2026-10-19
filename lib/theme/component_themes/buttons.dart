part of '../component_themes.dart';

ButtonStyle _filledButtonStyle(ColorScheme scheme, double radius) =>
    FilledButton.styleFrom(
      backgroundColor: scheme.brightness == Brightness.light
          ? scheme.onPrimaryContainer
          : scheme.primary,
      foregroundColor: scheme.onPrimary,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: AppType.scale.labelLarge,
    );

ButtonStyle _textButtonStyle(ColorScheme scheme, double radius) =>
    TextButton.styleFrom(
      foregroundColor: scheme.onPrimaryContainer,
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: AppType.scale.labelLarge,
    );
