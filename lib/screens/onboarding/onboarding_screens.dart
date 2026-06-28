import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../services/onboarding_prefs.dart';

class Onboarding1Screen extends StatelessWidget {
  const Onboarding1Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              // Illustration
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/onboarding/onboarding-1.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // Text content
              _OnboardingContent(
                title: 'Curate Words That Matter',
                subtitle:
                    'Join the largest community of people preserving mother tongues across the world.',
                activeIndex: 0,
                onSkip: () {
                  OnboardingPrefs.markSeen();
                  Navigator.of(context).pushReplacementNamed('/signin');
                },
                onNext: () => Navigator.of(context).pushNamed('/onboarding4'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Onboarding4Screen extends StatelessWidget {
  const Onboarding4Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/onboarding/onboarding-4.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              _OnboardingContent(
                title: 'Solve for Your Mother Tongue',
                subtitle:
                    'Every Neo gives your mother tongue a chance to survive in the 21st Century world.',
                activeIndex: 1,
                onSkip: () {
                  OnboardingPrefs.markSeen();
                  Navigator.of(context).pushReplacementNamed('/signin');
                },
                onNext: () => Navigator.of(context).pushNamed('/onboarding5'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Onboarding5Screen extends StatelessWidget {
  const Onboarding5Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/onboarding/onboarding-5.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              _OnboardingContent(
                title: 'Made By You For The World',
                subtitle:
                    'A modern living dictionary based on your votes, your words. Every vote shapes the future of your mother tongue.',
                activeIndex: 2,
                // Last screen — only Continue, no Skip
                onNext: () {
                  OnboardingPrefs.markSeen();
                  Navigator.of(context).pushReplacementNamed('/signin');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared bottom content ─────────────────────────────────────────────────────
class _OnboardingContent extends StatelessWidget {
  final String title;
  final String subtitle;
  final int activeIndex;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  const _OnboardingContent({
    required this.title,
    required this.subtitle,
    required this.activeIndex,
    required this.onNext,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Parkinsans',
            fontSize: 26,
            fontWeight: FontWeight.w500,
            height: 1.38,
            letterSpacing: -0.5,
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: 12),

        // Subtitle
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: AppColors.foreground80,
          ),
        ),
        const SizedBox(height: 28),

        // Progress dots
        OnboardingDots(activeIndex: activeIndex),
        const SizedBox(height: 28),

        // Buttons
        if (onSkip != null)
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Skip',
                  outlined: true,
                  onPressed: onSkip,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppButton(
                  label: 'Next',
                  onPressed: onNext,
                ),
              ),
            ],
          )
        else
          AppButton(
            label: 'Continue',
            onPressed: onNext,
          ),

        const SizedBox(height: 16),
      ],
    );
  }
}
