import 'package:flutter/material.dart';
import 'vote_screen.dart';

// Thin shell that re-uses all real jury logic from VoteScreen.
// The standalone JuryScreen widget was previously a stub with hardcoded
// fake data; now it delegates to VoteScreen(isJuror: true) so users
// always see live Supabase data.
class JuryScreen extends StatelessWidget {
  const JuryScreen({super.key});

  @override
  Widget build(BuildContext context) => const VoteScreen(isJuror: true);
}
