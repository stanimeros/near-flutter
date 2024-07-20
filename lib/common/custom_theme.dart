import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomTheme {
  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      textTheme: TextTheme(
        titleSmall: GoogleFonts.manrope(),
        titleMedium: GoogleFonts.manrope(),
        titleLarge: GoogleFonts.manrope(),
        bodySmall: GoogleFonts.manrope(),
        bodyMedium: GoogleFonts.manrope(),
        bodyLarge: GoogleFonts.manrope(),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        // selectedItemColor: const Color.fromARGB(255, 35, 35, 35),
        selectedLabelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.bold,
          fontSize: 12
        ),
        unselectedLabelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.bold,
          fontSize: 12
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(90, 40)
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          textStyle: WidgetStatePropertyAll(GoogleFonts.manrope(
            fontWeight: FontWeight.w500,
            fontSize: 16
          )),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
          // backgroundColor: const WidgetStatePropertyAll(Color.fromARGB(255, 230, 230, 230)),
          // foregroundColor:const WidgetStatePropertyAll(Colors.black),
          // overlayColor: const WidgetStatePropertyAll(Color.fromARGB(255, 220, 220, 220))
        )
      ),
    );
  }
}
