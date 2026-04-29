import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'screens/chat_screen.dart';
import 'utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _showLoginOptions = false;
  bool _isAuthenticating = false;

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

    try {
      final user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        _navigateToChat();
      } else {
        if (mounted) {
          setState(() {
            _showLoginOptions = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _showLoginOptions = true;
        });
      }
    }
  }

  void _navigateToChat() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ChatScreen()),
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isAuthenticating) return;
    
    setState(() => _isAuthenticating = true);
    
    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(googleProvider);
        _navigateToChat();
        return;
      }

      final GoogleSignIn googleSignIn = GoogleSignIn();
      
      // Clean previous sign-in state to avoid stale sessions
      await googleSignIn.signOut();
      
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        if (mounted) setState(() => _isAuthenticating = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      
      _navigateToChat();
    } catch (e) {
      print('SIGN-IN ERROR: $e');
      if (mounted) {
        String errorMsg = 'Sign in failed. Please try again.';
        if (e.toString().contains('People API')) {
          errorMsg = 'Setup incomplete: Please enable People API in Google Console and wait 5 minutes.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _handleGoogleSignIn,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
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

                  // Show circle only when NOT showing login options AND NOT authenticating
                  if (!_showLoginOptions && !_isAuthenticating)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppConstants.primaryColor.withOpacity(0.8),
                        ),
                      ),
                    )
                  else if (_showLoginOptions)
                    _buildLoginUI(),
                  
                  if (_isAuthenticating)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: CircularProgressIndicator(color: AppConstants.primaryColor),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginUI() {
    return Column(
      children: [
        GestureDetector(
          onTap: _handleGoogleSignIn,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/google_logo.png',
              height: 48,
              width: 48,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.account_circle,
                  size: 48,
                  color: AppConstants.primaryColor,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Sign up or Log in',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 60),
          OutlinedButton.icon(
            onPressed: () async {
              final Uri url = Uri.parse('https://drive.google.com/drive/folders/1FJ-Qp_SPkTmXM_zgAkCpbYZrLM5WoXgd');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.android, color: Colors.white, size: 18),
            label: Text(
              'Download Android App',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
