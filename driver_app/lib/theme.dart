import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design-system definition for Sarathi.
///
/// Color roles are kept as the same static constants used elsewhere in the
/// app (AppTheme.primaryColor, AppTheme.successColor, etc.) so no call sites
/// need to change — only the values, contrast, and theme completeness
/// have been reworked.
class AppTheme {
  // ── Brand palette ─────────────────────────────────────────────────────
  static const Color primaryColor      = Color(0xFF0B4FCC); // Deep confident blue
  static const Color primaryContainer  = Color(0xFF2F6FE4);
  static const Color primaryFixedDim   = Color(0xFFA9C4FF);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);

  static const Color secondaryColor    = Color(0xFF00785A); // Emerald green
  static const Color secondaryFixed    = Color(0xFF6BF6C9);

  static const Color tertiaryColor     = Color(0xFF7A4B00); // Amber-brown

  // ── Semantic status colors ────────────────────────────────────────────
  static const Color errorColor        = Color(0xFFBA1A1A);
  static const Color errorContainer    = Color(0xFFFFDAD6);
  static const Color successColor      = Color(0xFF00785A); // maps to secondary
  static const Color warningColor      = Color(0xFF7A4B00); // maps to tertiary
  static const Color emergencyColor    = Color(0xFFD32F2F);

  // ── Light surfaces ─────────────────────────────────────────────────────
  static const Color background            = Color(0xFFF7F8FC);
  static const Color surfaceLowest         = Color(0xFFFFFFFF);
  static const Color surfaceContainer      = Color(0xFFEDF1FB);
  static const Color surfaceContainerLow   = Color(0xFFF2F4FC);
  static const Color surfaceContainerHigh  = Color(0xFFE3E9FA);
  static const Color surfaceVariant        = Color(0xFFDCE4F7);
  static const Color outlineVariant        = Color(0xFFD3D6E3);
  static const Color outline               = Color(0xFF7C7F91);

  // ── Light on-colors ────────────────────────────────────────────────────
  static const Color onSurface         = Color(0xFF10151F);
  static const Color onSurfaceVariant  = Color(0xFF444859);
  static const Color onPrimary         = Color(0xFFFFFFFF);
  static const Color onSecondary       = Color(0xFFFFFFFF);
  static const Color onError           = Color(0xFFFFFFFF);

  // ── Secondary theme palette ────────────────────────────────────────────
  // Kept as a distinct color set from the primary light theme (different
  // primary tone, still white/light backgrounds — no black anywhere).
  static const Color darkPrimary          = Color(0xFF0B4FCC);
  static const Color darkOnPrimary        = Color(0xFFFFFFFF);
  static const Color darkPrimaryContainer = Color(0xFFDCE7FF);
  static const Color darkSecondary        = Color(0xFF00785A);
  static const Color darkOnSecondary      = Color(0xFFFFFFFF);
  static const Color darkError            = Color(0xFFBA1A1A);
  static const Color darkOnError          = Color(0xFFFFFFFF);

  static const Color darkBackground    = Color(0xFFFFFFFF);
  static const Color darkSurface       = Color(0xFFFFFFFF);
  static const Color darkSurfaceHigh   = Color(0xFFF2F4FC);
  static const Color darkOutline       = Color(0xFF7C7F91);
  static const Color darkOutlineVariant = Color(0xFFD3D6E3);
  static const Color darkText          = Color(0xFF10151F);
  static const Color darkTextMuted     = Color(0xFF444859);

  // ── Shared metrics ─────────────────────────────────────────────────────
  static const double radiusSm  = 10;
  static const double radiusMd  = 14;
  static const double radiusLg  = 20;
  static const double radiusXl  = 28;

  // ── Typography helper ─────────────────────────────────────────────────
  static TextTheme get _plusJakartaTextTheme =>
      GoogleFonts.plusJakartaSansTextTheme();

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    return _plusJakartaTextTheme
        .apply(bodyColor: bodyColor, displayColor: displayColor)
        .copyWith(
          headlineSmall: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: displayColor,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: displayColor,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: displayColor,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: bodyColor,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.45,
            color: bodyColor,
          ),
        );
  }

  // ── Light Theme ────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme(onSurface, onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary:                 primaryColor,
        primaryContainer:        primaryContainer,
        onPrimaryContainer:      onPrimaryContainer,
        secondary:               secondaryColor,
        secondaryContainer:      secondaryFixed,
        tertiary:                tertiaryColor,
        error:                   errorColor,
        errorContainer:          errorContainer,
        surface:                 surfaceLowest,
        onPrimary:               onPrimary,
        onSecondary:             onSecondary,
        onSurface:               onSurface,
        onSurfaceVariant:        onSurfaceVariant,
        onError:                 onError,
        outline:                 outline,
        outlineVariant:          outlineVariant,
        surfaceContainerLowest:  surfaceLowest,
        surfaceContainerLow:     surfaceContainerLow,
        surfaceContainer:        surfaceContainer,
        surfaceContainerHigh:    surfaceContainerHigh,
        surfaceContainerHighest: surfaceVariant,
      ),
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        iconTheme: const IconThemeData(color: onSurface),
      ),

      cardTheme: CardThemeData(
        color: surfaceLowest,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: outlineVariant.withValues(alpha: 0.5)),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.35),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: outlineVariant),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryColor, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: errorColor, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: errorColor, width: 1.6),
        ),
        prefixIconColor: outline,
        suffixIconColor: outline,
        hintStyle: GoogleFonts.plusJakartaSans(
          color: outline,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(
          color: primaryColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        errorStyle: GoogleFonts.plusJakartaSans(
          color: errorColor,
          fontSize: 12,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceLowest,
        selectedItemColor: primaryColor,
        unselectedItemColor: outline,
        selectedLabelStyle:
            GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceLowest,
        indicatorColor: primaryColor.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryColor : outline,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? primaryColor : outline);
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: outlineVariant, width: 1.4),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : outline),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onPrimary : surfaceLowest),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? primaryColor
                : outlineVariant),
        trackOutlineColor:
            WidgetStateProperty.all(Colors.transparent),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        circularTrackColor: surfaceContainerHigh,
        linearTrackColor: surfaceContainerHigh,
      ),

      dividerTheme: const DividerThemeData(
        color: outlineVariant,
        thickness: 1,
        space: 1,
      ),

      iconTheme: const IconThemeData(color: onSurfaceVariant, size: 22),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primaryColor.withValues(alpha: 0.14),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurface,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: surfaceLowest,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        actionTextColor: primaryFixedDim,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceVariant,
        textColor: onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: outline,
        labelStyle:
            GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 14),
        indicatorColor: primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outlineVariant,
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(surfaceLowest),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
        ),
      ),
    );
  }

  // ── Dark Theme ────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final textTheme = _buildTextTheme(darkText, darkText);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary:                 darkPrimary,
        onPrimary:               darkOnPrimary,
        primaryContainer:        darkPrimaryContainer,
        onPrimaryContainer:      darkText,
        secondary:               darkSecondary,
        onSecondary:             darkOnSecondary,
        tertiary:                secondaryFixed,
        error:                   darkError,
        onError:                 darkOnError,
        surface:                 darkSurface,
        onSurface:               darkText,
        onSurfaceVariant:        darkTextMuted,
        outline:                 darkOutline,
        outlineVariant:          darkOutlineVariant,
        surfaceContainerLowest:  darkBackground,
        surfaceContainerLow:     darkSurface,
        surfaceContainer:        darkSurfaceHigh,
        surfaceContainerHigh:    darkSurfaceHigh,
        surfaceContainerHighest: darkSurfaceHigh,
      ),
      scaffoldBackgroundColor: darkBackground,
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: darkText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        iconTheme: const IconThemeData(color: darkText),
      ),

      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: darkOutlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          side: const BorderSide(color: darkOutlineVariant),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkOutlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkOutlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkPrimary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkError, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkError, width: 1.6),
        ),
        prefixIconColor: darkTextMuted,
        suffixIconColor: darkTextMuted,
        hintStyle: GoogleFonts.plusJakartaSans(
          color: darkTextMuted,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: darkTextMuted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(
          color: darkPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: darkPrimary,
        unselectedItemColor: darkOutline,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: darkPrimary.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? darkPrimary : null),
        checkColor: WidgetStateProperty.all(darkOnPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: darkOutlineVariant, width: 1.4),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? darkPrimary
                : darkOutline),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? darkOnPrimary
                : darkSurfaceHigh),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? darkPrimary
                : darkOutlineVariant),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkPrimary,
        circularTrackColor: darkSurfaceHigh,
        linearTrackColor: darkSurfaceHigh,
      ),

      dividerTheme: const DividerThemeData(
        color: darkOutlineVariant,
        thickness: 1,
        space: 1,
      ),

      iconTheme: const IconThemeData(color: darkTextMuted, size: 22),

      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceHigh,
        selectedColor: darkPrimary.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: darkTextMuted,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceHigh,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: darkText,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        actionTextColor: darkPrimary,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: darkTextMuted,
        textColor: darkText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: darkPrimary,
        unselectedLabelColor: darkOutline,
        labelStyle:
            GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 14),
        indicatorColor: darkPrimary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: darkOutlineVariant,
      ),
    );
  }
}