import 'package:flutter/material.dart';
import 'package:flutter_near/common/auth_service.dart';
import 'package:flutter_near/widgets/custom_loader.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  bool isLoading = false;
  bool isRegistering = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailPasswordAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    final success = isRegistering
        ? await AuthService().registerWithEmailPassword(
            _emailController.text,
            _passwordController.text,
          )
        : await AuthService().signInWithEmailPassword(
            _emailController.text,
            _passwordController.text,
          );

    if (!success) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: SizedBox(
            height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        isRegistering = !isRegistering;
                      });
                    },
                    child: Text(
                      isRegistering
                          ? 'Already have an account? Sign In'
                          : 'Need an account? Register',
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Near',
                    style: TextStyle(fontSize: 36, letterSpacing: 4),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 400,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Visibility(
                          visible: isLoading,
                          child: const CustomLoader(),
                        ),
                        Visibility(
                          visible: !isLoading,
                          child: Column(
                            children: [
                              Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _emailController,
                                      decoration: const InputDecoration(
                                        labelText: 'Email',
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _passwordController,
                                      decoration: const InputDecoration(
                                        labelText: 'Password',
                                      ),
                                      obscureText: true,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your password';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton(
                                      onPressed: _handleEmailPasswordAuth,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            isRegistering ? 'Register' : 'Sign In',
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}