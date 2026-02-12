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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFEAF1FA),
        fontFamily: 'Noto Sans TC',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
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
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
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
            borderSide: const BorderSide(color: Color(0xFF0E5AA7), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        textTheme: ThemeData.light(useMaterial3: true).textTheme.copyWith(
          headlineSmall: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: Color(0xFF10253D),
          ),
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10253D),
          ),
          titleMedium: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF183C61),
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Color(0xFF2A4057),
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: Color(0xFF58708C),
          ),
        ),
      ),
      home: const InsuranceHomePage(),
    );
  }
}
