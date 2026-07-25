import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/chat_screen.dart';
import 'utils/constants.dart';

class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
    _handleNavigation();
  }

  Future<void> _handleNavigation() async {
    // Always wait at least 2.5 seconds to show the branding
    await Future.delayed(const Duration(milliseconds: 2500));

    // No forced sign-in here — the app is usable as a guest right away.
    // Signing in is offered contextually inside the chat screen (drawer /
    // menu) only when the user actually wants synced history or tokens.
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ChatScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image with dim overlay
          Positioned.fill(
            child: Stack(
              children: [
                Image.asset(
                  'assets/splash_background.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                ),
                Container(
                  color: Colors.black.withOpacity(0.7),
                ),
              ],
            ),
          ),

          // Content
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo / Branding
                  ShaderMask(
                    shaderCallback: (bounds) => AppConstants.primaryGradient.createShader(bounds),
                    child: Text(
                      'Nyxra',
                      style: GoogleFonts.poppins(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Text(
                    'AI',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      color: Colors.white.withOpacity(0.8),
                      letterSpacing: 4,
                    ),
                  ),

                  const SizedBox(height: 60),

                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppConstants.primaryColor.withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
