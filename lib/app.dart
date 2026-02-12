import 'package:flutter/material.dart';

import 'pages/insurance_home_page.dart';

class InsuranceAdvisorApp extends StatelessWidget {
  const InsuranceAdvisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E5AA7),
      brightness: Brightness.light,
    );
    final colorScheme = baseScheme.copyWith(
      primary: const Color(0xFF0E5AA7),
      secondary: const Color(0xFF1D9D8E),
      tertiary: const Color(0xFFDD8B2A),
      surface: const Color(0xFFFFFFFF),
      surfaceContainerHighest: const Color(0xFFDCE8F5),
      outlineVariant: const Color(0xFFC5D6EA),
    );

    return MaterialApp(
      title: '個人保險顧問',
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: const TextScaler.linear(1.15)),
          child: child!,
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFEAF1FA),
        fontFamily: 'Noto Sans TC',
        visualDensity: VisualDensity.comfortable,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F2F4D),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xF8FFFFFF),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0x80C9DBEF)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xF5FFFFFF),
          indicatorColor: const Color(0xFFCEE5FF),
          elevation: 0,
          height: 80,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? const Color(0xFF0C3F79)
                  : const Color(0xFF516274),
            );
          }),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF0E5AA7),
          foregroundColor: Colors.white,
          elevation: 2,
          shape: StadiumBorder(),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 4),
          minVerticalPadding: 10,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 7,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 20),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F7FD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC3D5EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC3D5EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF0E5AA7), width: 1.8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        textTheme: ThemeData.light(useMaterial3: true).textTheme.copyWith(
          headlineSmall: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: Color(0xFF10253D),
          ),
          titleLarge: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10253D),
          ),
          titleMedium: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF183C61),
          ),
          bodyMedium: const TextStyle(
            fontSize: 17,
            height: 1.35,
            color: Color(0xFF20374E),
          ),
          bodySmall: const TextStyle(
            fontSize: 15,
            height: 1.35,
            color: Color(0xFF3F5873),
          ),
        ),
      ),
      home: const InsuranceHomePage(),
    );
  }
}
