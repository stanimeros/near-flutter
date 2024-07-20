import 'package:flutter/material.dart';
import 'package:flutter_near/common/auth_service.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:lucide_icons/lucide_icons.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Text(
              'Near',
              style: TextStyle(
                fontSize: 36,
                letterSpacing: 4
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 240,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Visibility(
                    visible: isLoading,
                    child: const CustomLoader()
                  ),
                  Visibility(
                    visible: !isLoading,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                isLoading = true;
                              });
                          
                              if (!await AuthService().signInWithGoogle()){
                                setState(() {
                                  isLoading = false;
                                });
                              }
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Sign in with Google',
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  size: 18,
                                  LucideIcons.logIn
                                )
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}