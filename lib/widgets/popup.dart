import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PopUp extends AlertDialog {
  final String textBtn1;
  final String textBtn2;
  final String textTitle;
  final VoidCallback funBtn1;
  final VoidCallback funBtn2;

  const PopUp({
    super.key,
    this.textBtn1 = 'Yes',
    this.textBtn2 = 'No',
    this.textTitle = 'Are you sure?',
    required this.funBtn1,
    required this.funBtn2,
  });


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 17,
      ),
      title:  Text(
        textTitle,
        textAlign: TextAlign.center,
      ),
      content: Row(
        children: [
          const Spacer(),
          ElevatedButton(
            onPressed: funBtn1,
            child: Text(textBtn1)
          ),
          const SizedBox(width: 30),
          ElevatedButton(
            onPressed: funBtn2,
            child: Text(textBtn2)
          ),
          const Spacer(),
        ],
      ),
    
    );
  }
}