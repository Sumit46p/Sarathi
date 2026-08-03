import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design-system definition for Sarathi Driver App.
/// Matches the design reference with teal/green primary colors.
class AppTheme {
  // ── Brand palette ─────────────────────────────────────────────────────
  static const Color primaryColor      = Color(0xFF0D7377); // Teal/Green from design
  static const Color primaryLight      = Color(0xFF14919A);
  static const Color primaryDark       = Color(0xFF095C5F);
  static const Color primaryContainer  = Color(0xFF14919A); // For backward compatibility
  
  static const Color secondaryColor    = Color(0xFF14B8A6); // Lighter teal for accents
  static const Color accentColor       = Color(0xFF2DD4BF);
  
  // ── Semantic status colors ────────────────────────────────────────────
  static const Color errorColor        = Color(0xFFDC2626);
  static const Color errorLight        = Color(0xFFFEE2E2);
  static const Color successColor      = Color(0xFF059669);
  static const Color successLight      = Color(0xFFD1FAE5);
  static const Color warningColor      = Color(0xFFF59E0B);
  static const Color warningLight      = Color(0xFFFEF3C7);
  static const Color urgentColor       = Color(0xFFDC2626);
  static const Color urgentLight       = Color(0xFFFEE2E2);

  // ── Light surfaces ─────────────────────────────────────────────────────
  static const Color background        = Color(0xFFF8FAFC);
  static const Color surface           = Color(0xFFFFFFFF);
  static const Color surfaceVariant    = Color(0xFFF1F5F9);
  static const Color surfaceElevated   = Color(0xFFFFFFFF);
  static const Color surfaceLowest     = Color(0xFFF8FAFC); // For backward compatibility
  
  // ── Text colors ────────────────────────────────────────────────────────
  static const Color onSurface         = Color(0xFF0F172A);
  static const Color onSurfaceVariant  = Color(0xFF64748B);
  static const Color onPrimary         = Color(0xFFFFFFFF);
  static const Color onSecondary       = Color(0xFFFFFFFF);
  
  // ── Border & Divider ───────────────────────────────────────────────────
  static const Color outline           = Color(0xFFCBD5E1);
  static const Color outlineVariant    = Color(0xFFE2E8F0);
  static const Color divider           = Color(0xFFE2E8F0);

  // ── Shared metrics ─────────────────────────────────────────────────────
  static const double radiusSm  = 8;
  static const double radiusMd  = 12;
  static const double radiusLg  = 16;
  static const double radiusXl  = 24;
  static const double radiusFull = 999;

  // ── Typography helper ─────────────────────────────────────────────────
  static TextTheme get _interTextTheme => GoogleFonts.interTextTheme();

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    return _interTextTheme
        .apply(bodyColor: bodyColor, displayColor: displayColor)
        .copyWith(
          headlineLarge: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: displayColor,
          ),
          headlineMedium: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: displayColor,
          ),
          headlineSmall: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: displayColor,
          ),
          titleLarge: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: displayColor,
          ),
          titleMedium: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: displayColor,
          ),
          titleSmall: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: displayColor,
          ),
          labelLarge: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: bodyColor,
          ),
          labelMedium: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: bodyColor,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 16,
            height: 1.5,
            color: bodyColor,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: bodyColor,
          ),
          bodySmall: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
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
        onPrimary:               onPrimary,
        primaryContainer:        primaryLight,
        onPrimaryContainer:      onPrimary,
        secondary:               secondaryColor,
        onSecondary:             onSecondary,
        secondaryContainer:      successLight,
        onSecondaryContainer:    successColor,
        error:                   errorColor,
        onError:                 Colors.white,
        errorContainer:          errorLight,
        surface:                 surface,
        onSurface:               onSurface,
        onSurfaceVariant:        onSurfaceVariant,
        outline:                 outline,
        outlineVariant:          outlineVariant,
        surfaceContainerLowest:  background,
        surfaceContainerLow:     surfaceVariant,
        surfaceContainer:        surface,
        surfaceContainerHigh:    surfaceElevated,
      ),
      scaffoldBackgroundColor: background,
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        iconTheme: const IconThemeData(color: onSurface, size: 24),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: onPrimary,
          disabledBackgroundColor: primaryColor.withOpacity(0.4),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
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
          side: const BorderSide(color: outline),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: errorColor, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        hintStyle: GoogleFonts.inter(
          color: onSurfaceVariant,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.inter(
          color: onSurfaceVariant,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: primaryColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        errorStyle: GoogleFonts.inter(
          color: errorColor,
          fontSize: 12,
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primaryColor,
        unselectedItemColor: onSurfaceVariant,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primaryColor.withOpacity(0.12),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? primaryColor : onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? primaryColor : onSurfaceVariant);
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: outline, width: 1.5),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : outline),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onPrimary : surface),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryColor : outline),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
        circularTrackColor: surfaceVariant,
        linearTrackColor: surfaceVariant,
      ),

      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      iconTheme: const IconThemeData(color: onSurfaceVariant, size: 24),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        selectedColor: primaryColor.withOpacity(0.15),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: onSurfaceVariant,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurface,
        contentTextStyle: GoogleFonts.inter(
          color: surface,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        actionTextColor: accentColor,
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
        unselectedLabelColor: onSurfaceVariant,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        indicatorColor: primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: divider,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),
    );
  }

  // ── Dark Theme (placeholder for backward compatibility) ────────────────
  static ThemeData get darkTheme => lightTheme;
}
