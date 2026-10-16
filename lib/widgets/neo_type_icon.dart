import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class NeoTypeIcon extends StatelessWidget {
  final String type;
  const NeoTypeIcon({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    // Match the web Voting Page's Lucide icons, including its legacy alias.
    final icon = switch (type.toUpperCase()) {
      'POPULAR' => 'star',
      'ADOPTIVE' => 'recycle',
      'FUNCTIONAL' => 'wrench',
      'ROOT' => 'tree-palm',
      'CREATIVE' || 'NON-CONFORMING' => 'brain',
      _ => 'circle',
    };
    return SvgPicture.asset(
      'assets/neo-types/$icon.svg',
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFA3A3A3)
            : const Color(0xFF525252),
        BlendMode.srcIn,
      ),
    );
  }
}
